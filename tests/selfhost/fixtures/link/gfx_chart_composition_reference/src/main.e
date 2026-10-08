// The mekko, Euler, Venn and word-cloud layouts of e.gfx.chart against independent numpy and scipy
// computations (L073, D2257; scripts/chart_composition_reference.py writes this file): cell areas as value
// over grand total, circle areas and the overlap-solving centre distance, Venn spacing and region membership,
// and the cloud's sizes, order, exclusions, containment and spacing. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os
use e.str

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn close32(got: f32, want: f32, tolerance: f64) -> bool {
    ret close(f64(got), f64(want), tolerance)
}

fn circle_distance(a: geometry.Rect, b: geometry.Rect) -> f32 {
    let dx = f64(a.x + a.width * 0.5) - f64(b.x + b.width * 0.5)
    let dy = f64(a.y + a.height * 0.5) - f64(b.y + b.height * 0.5)
    ret f32(math_sqrt(dx * dx + dy * dy))
}

fn math_sqrt(v: f64) -> f64 {
    if v <= 0.0f64 { ret 0.0f64 }
    var x = v
    var i = 0usize
    while i < 80usize {
        x = 0.5f64 * (x + v / x)
        i += 1usize
    }
    ret x
}

fn inside(circle: geometry.Rect, p: chart.Coord) -> bool {
    let r = f64(circle.width) * 0.5f64
    let dx = f64(p.x) - (f64(circle.x) + r)
    let dy = f64(p.y) - (f64(circle.y) + r)
    ret dx * dx + dy * dy < r * r
}

// Lens area by numerical integration over x, so it shares no formula with the library.
fn lens_area(a: geometry.Rect, b: geometry.Rect) -> f64 {
    let ra = f64(a.width) * 0.5f64
    let rb = f64(b.width) * 0.5f64
    let ax = f64(a.x) + ra
    let ay = f64(a.y) + ra
    let bx = f64(b.x) + rb
    let by = f64(b.y) + rb
    var left = ax - ra
    if bx - rb > left { left = bx - rb }
    var right = ax + ra
    if bx + rb < right { right = bx + rb }
    if right <= left { ret 0.0f64 }
    let steps = 20000usize
    let h = (right - left) / f64(steps)
    var area = 0.0f64
    var i = 0usize
    while i < steps {
        let x = left + (f64(i) + 0.5f64) * h
        let ua = ra * ra - (x - ax) * (x - ax)
        let ub = rb * rb - (x - bx) * (x - bx)
        if ua > 0.0f64 && ub > 0.0f64 {
            let sa = math_sqrt(ua)
            let sb = math_sqrt(ub)
            var low = ay - sa
            if by - sb > low { low = by - sb }
            var high = ay + sa
            if by + sb < high { high = by + sb }
            if high > low { area += (high - low) * h }
        }
        i += 1usize
    }
    ret area
}

fn cloud_contained(cloud: []chart.CloudWord, bounds: geometry.Rect) -> bool {
    var i = 0usize
    while i < cloud.len {
        let b = cloud[i].box
        if b.x < bounds.x || b.y < bounds.y || b.x + b.width > bounds.x + bounds.width || b.y + b.height > bounds.y + bounds.height { ret false }
        i += 1usize
    }
    ret true
}

fn cloud_overlaps(cloud: []chart.CloudWord, gap: f32) -> bool {
    var i = 0usize
    while i < cloud.len {
        var j = 0usize
        while j < i {
            let a = cloud[i].box
            let b = cloud[j].box
            if a.x < b.x + b.width + gap && a.x + a.width + gap > b.x && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y { ret true }
            j += 1usize
        }
        i += 1usize
    }
    ret false
}

fn cloud_has(cloud: []chart.CloudWord, text: str) -> bool {
    var i = 0usize
    while i < cloud.len {
        if str.eq(cloud[i].label.text, text) { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let mekko_values = [24]f32{ 7.91f32, 0.76f32, 0.75f32, 2.98f32, 6.77f32, 1.38f32, 0.0f32, 2.66f32, 3.38f32, 4.37f32, 3.54f32, 3.96f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 3.57f32, 8.96f32, 0.0f32, 8.37f32, 2.84f32, 3.99f32, 8.73f32 }
    let mekko_bounds = geometry.rect(10.0, 20.0, 240.0, 160.0)
    var mekko_totals: [6]f64 = zero
    var mekko_bars: [24]geometry.Rect = zero
    var mekko_layers: [4]chart.Layout = zero
    let (mekko_made, mekko_error) = chart.mekko(mekko_values[..], 6usize, 4usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])
    if mekko_error != ok || mekko_made.len != 4usize { os.exit(1) }
    if !close(mekko_totals[0], 12.4f64, 1e-6) || !close(mekko_totals[1], 10.809999999999999f64, 1e-6) || !close(mekko_totals[2], 15.25f64, 1e-6) || !close(mekko_totals[3], 0.0f64, 1e-6) || !close(mekko_totals[4], 12.530000000000001f64, 1e-6) || !close(mekko_totals[5], 23.93f64, 1e-6) { os.exit(2) }
    if !close32(mekko_bars[0].width * mekko_bars[0].height / 38400.0f32, 0.10557928457020824f32, 1e-5) || !close32(mekko_bars[6].width * mekko_bars[6].height / 38400.0f32, 0.010144153764014952f32, 1e-5) || !close32(mekko_bars[12].width * mekko_bars[12].height / 38400.0f32, 0.010010678056593702f32, 1e-5) || !close32(mekko_bars[18].width * mekko_bars[18].height / 38400.0f32, 0.03977576081153231f32, 1e-5) || !close32(mekko_bars[1].width * mekko_bars[1].height / 38400.0f32, 0.09036305392418581f32, 1e-5) || !close32(mekko_bars[7].width * mekko_bars[7].height / 38400.0f32, 0.01841964762413241f32, 1e-5) || !close32(mekko_bars[13].width * mekko_bars[13].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[19].width * mekko_bars[19].height / 38400.0f32, 0.03550453817405233f32, 1e-5) || !close32(mekko_bars[2].width * mekko_bars[2].height / 38400.0f32, 0.04511478910838228f32, 1e-5) || !close32(mekko_bars[8].width * mekko_bars[8].height / 38400.0f32, 0.05832888414308597f32, 1e-5) || !close32(mekko_bars[14].width * mekko_bars[14].height / 38400.0f32, 0.04725040042712227f32, 1e-5) || !close32(mekko_bars[20].width * mekko_bars[20].height / 38400.0f32, 0.052856380138814746f32, 1e-5) || !close32(mekko_bars[3].width * mekko_bars[3].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[9].width * mekko_bars[9].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[15].width * mekko_bars[15].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[21].width * mekko_bars[21].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[4].width * mekko_bars[4].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[10].width * mekko_bars[10].height / 38400.0f32, 0.047650827549386016f32, 1e-5) || !close32(mekko_bars[16].width * mekko_bars[16].height / 38400.0f32, 0.11959423384943943f32, 1e-5) || !close32(mekko_bars[22].width * mekko_bars[22].height / 38400.0f32, 0.0f32, 1e-5) || !close32(mekko_bars[5].width * mekko_bars[5].height / 38400.0f32, 0.1117191671115857f32, 1e-5) || !close32(mekko_bars[11].width * mekko_bars[11].height / 38400.0f32, 0.037907100907634814f32, 1e-5) || !close32(mekko_bars[17].width * mekko_bars[17].height / 38400.0f32, 0.053256807261078495f32, 1e-5) || !close32(mekko_bars[23].width * mekko_bars[23].height / 38400.0f32, 0.11652429257875069f32, 1e-5) { os.exit(3) }
    if !close32(mekko_bars[0].x, 10.0f32, 1e-4) || !close32(mekko_bars[0].width, 39.72237052856381f32, 1e-4) || !close32(mekko_bars[1].x, 49.72237052856381f32, 1e-4) || !close32(mekko_bars[1].width, 34.628937533368926f32, 1e-4) || !close32(mekko_bars[2].x, 84.35130806193274f32, 1e-4) || !close32(mekko_bars[2].width, 48.852108916177265f32, 1e-4) || mekko_bars[3].width != 0.0 || !close32(mekko_bars[4].x, 133.20341697811f32, 1e-4) || !close32(mekko_bars[4].width, 40.13881473571811f32, 1e-4) || !close32(mekko_bars[5].x, 173.3422317138281f32, 1e-4) || !close32(mekko_bars[5].width, 76.65776828617193f32, 1e-4) { os.exit(4) }
    if !close32(mekko_bars[0].y + mekko_bars[0].height, 180.0f32, 1e-4) || !close32(mekko_bars[6].y + mekko_bars[6].height, 77.93548387096774f32, 1e-4) || !close32(mekko_bars[12].y + mekko_bars[12].height, 68.12903225806451f32, 1e-4) || !close32(mekko_bars[18].y + mekko_bars[18].height, 58.45161290322581f32, 1e-4) || !close32(mekko_bars[1].y + mekko_bars[1].height, 180.0f32, 1e-4) || !close32(mekko_bars[7].y + mekko_bars[7].height, 79.79648473635523f32, 1e-4) || !close32(mekko_bars[13].y + mekko_bars[13].height, 59.370952821461614f32, 1e-4) || !close32(mekko_bars[19].y + mekko_bars[19].height, 59.370952821461614f32, 1e-4) || !close32(mekko_bars[2].y + mekko_bars[2].height, 180.0f32, 1e-4) || !close32(mekko_bars[8].y + mekko_bars[8].height, 144.5377049180328f32, 1e-4) || !close32(mekko_bars[14].y + mekko_bars[14].height, 98.68852459016394f32, 1e-4) || !close32(mekko_bars[20].y + mekko_bars[20].height, 61.54754098360657f32, 1e-4) || !close32(mekko_bars[4].y + mekko_bars[4].height, 180.0f32, 1e-4) || !close32(mekko_bars[10].y + mekko_bars[10].height, 180.0f32, 1e-4) || !close32(mekko_bars[16].y + mekko_bars[16].height, 134.41340782122904f32, 1e-4) || !close32(mekko_bars[22].y + mekko_bars[22].height, 20.0f32, 1e-4) || !close32(mekko_bars[5].y + mekko_bars[5].height, 180.0f32, 1e-4) || !close32(mekko_bars[11].y + mekko_bars[11].height, 124.03677392394485f32, 1e-4) || !close32(mekko_bars[17].y + mekko_bars[17].height, 105.04805683242793f32, 1e-4) || !close32(mekko_bars[23].y + mekko_bars[23].height, 78.37024655244463f32, 1e-4) { os.exit(5) }
    let mekko_bad = [4]f32{ 1.0, 2.0, -1.0, 4.0 }
    let (_, mekko_negative) = chart.mekko(mekko_bad[..], 2usize, 2usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])
    let mekko_zero = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let (_, mekko_none) = chart.mekko(mekko_zero[..], 2usize, 2usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])
    let (_, mekko_short) = chart.mekko(mekko_values[..], 6usize, 4usize, mekko_bounds, mekko_totals[..5usize], mekko_bars[..], mekko_layers[..])
    let (_, mekko_empty) = chart.mekko(mekko_values[..0usize], 0usize, 4usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])
    if mekko_negative != chart.Invalid || mekko_none != chart.Empty || mekko_short != chart.TooLarge || mekko_empty != chart.Empty { os.exit(6) }
    let euler_bounds = geometry.rect(0.0, 0.0, 300.0, 200.0)
    var euler_circles: [2]geometry.Rect = zero
    var euler_layers: [2]chart.Layout = zero
    let (euler_0, euler_0_error) = chart.euler2(10.0f32, 6.0f32, 2.0f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_0_error != ok || euler_0.len != 2usize { os.exit(7) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 1.2909944487358056f32, 1e-5) { os.exit(8) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 1.4363663774320692f32, 1e-4) { os.exit(9) }
    if !close(lens_area(euler_circles[0], euler_circles[1]) / (3.141592653589793f64 * f64(euler_circles[0].width) * f64(euler_circles[0].width) * 0.25f64), 0.2f64, 1e-4) { os.exit(10) }
    let (euler_1, euler_1_error) = chart.euler2(10.0f32, 10.0f32, 5.0f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_1_error != ok || euler_1.len != 2usize { os.exit(11) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 1.0f32, 1e-5) { os.exit(12) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 0.8079455065990347f32, 1e-4) { os.exit(13) }
    if !close(lens_area(euler_circles[0], euler_circles[1]) / (3.141592653589793f64 * f64(euler_circles[0].width) * f64(euler_circles[0].width) * 0.25f64), 0.5f64, 1e-4) { os.exit(14) }
    let (euler_2, euler_2_error) = chart.euler2(7.0f32, 3.0f32, 3.0f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_2_error != ok || euler_2.len != 2usize { os.exit(15) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 1.5275252316519468f32, 1e-5) { os.exit(16) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 0.0f32, 1e-4) { os.exit(17) }
    let (euler_3, euler_3_error) = chart.euler2(4.0f32, 9.0f32, 0.0f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_3_error != ok || euler_3.len != 2usize { os.exit(18) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 0.6666666666666666f32, 1e-5) { os.exit(19) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 1.7866666666666664f32, 1e-4) { os.exit(20) }
    let (euler_4, euler_4_error) = chart.euler2(5.0f32, 5.0f32, 5.0f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_4_error != ok || euler_4.len != 2usize { os.exit(21) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 1.0f32, 1e-5) { os.exit(22) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 0.0f32, 1e-4) { os.exit(23) }
    let (euler_5, euler_5_error) = chart.euler2(1.0f32, 20.0f32, 0.3f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_5_error != ok || euler_5.len != 2usize { os.exit(24) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 0.22360679774997894f32, 1e-5) { os.exit(25) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 1.0641396558669964f32, 1e-4) { os.exit(26) }
    if !close(lens_area(euler_circles[0], euler_circles[1]) / (3.141592653589793f64 * f64(euler_circles[0].width) * f64(euler_circles[0].width) * 0.25f64), 0.3f64, 1e-4) { os.exit(27) }
    let (euler_6, euler_6_error) = chart.euler2(12.0f32, 8.0f32, 7.9f32, euler_bounds, euler_circles[..], euler_layers[..])
    if euler_6_error != ok || euler_6.len != 2usize { os.exit(28) }
    if !close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), 1.224744871391589f32, 1e-5) { os.exit(29) }
    if !close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), 0.2702652803807694f32, 1e-4) { os.exit(30) }
    if !close(lens_area(euler_circles[0], euler_circles[1]) / (3.141592653589793f64 * f64(euler_circles[0].width) * f64(euler_circles[0].width) * 0.25f64), 0.6583333333333333f64, 1e-4) { os.exit(31) }
    let (_, euler_big) = chart.euler2(5.0, 6.0, 7.0, euler_bounds, euler_circles[..], euler_layers[..])
    let (_, euler_neg) = chart.euler2(5.0, 6.0, -1.0, euler_bounds, euler_circles[..], euler_layers[..])
    let (_, euler_none) = chart.euler2(0.0, 0.0, 0.0, euler_bounds, euler_circles[..], euler_layers[..])
    let (_, euler_room) = chart.euler2(5.0, 6.0, 1.0, euler_bounds, euler_circles[..1usize], euler_layers[..])
    if euler_big != chart.Invalid || euler_neg != chart.Invalid || euler_none != chart.Empty || euler_room != chart.TooLarge { os.exit(32) }
    let venn_bounds = geometry.rect(0.0, 0.0, 240.0, 200.0)
    var venn_circles: [3]geometry.Rect = zero
    var venn_anchors: [7]chart.Coord = zero
    var venn_layers: [3]chart.Layout = zero
    let (venn_made, venn_error) = chart.venn3(venn_bounds, venn_circles[..], venn_anchors[..], venn_layers[..])
    if venn_error != ok || venn_made.len != 3usize { os.exit(33) }
    if !close32(venn_circles[0].width, venn_circles[1].width, 1e-5) || !close32(venn_circles[1].width, venn_circles[2].width, 1e-5) || !close32(venn_circles[0].height, venn_circles[0].width, 1e-5) { os.exit(34) }
    if !close32(circle_distance(venn_circles[0], venn_circles[1]), 1.15 * venn_circles[0].width * 0.5, 1e-4) || !close32(circle_distance(venn_circles[0], venn_circles[2]), 1.15 * venn_circles[0].width * 0.5, 1e-4) || !close32(circle_distance(venn_circles[1], venn_circles[2]), 1.15 * venn_circles[0].width * 0.5, 1e-4) { os.exit(35) }
    if venn_circles[0].x < 0.0 || venn_circles[1].x < 0.0 || venn_circles[2].x + venn_circles[2].width > 240.0 || venn_circles[0].y < 0.0 || venn_circles[1].y + venn_circles[1].height > 200.0 { os.exit(36) }
    if inside(venn_circles[0], venn_anchors[0]) != true || inside(venn_circles[1], venn_anchors[0]) != false || inside(venn_circles[2], venn_anchors[0]) != false { os.exit(37) }
    if inside(venn_circles[0], venn_anchors[1]) != false || inside(venn_circles[1], venn_anchors[1]) != true || inside(venn_circles[2], venn_anchors[1]) != false { os.exit(38) }
    if inside(venn_circles[0], venn_anchors[2]) != false || inside(venn_circles[1], venn_anchors[2]) != false || inside(venn_circles[2], venn_anchors[2]) != true { os.exit(39) }
    if inside(venn_circles[0], venn_anchors[3]) != true || inside(venn_circles[1], venn_anchors[3]) != true || inside(venn_circles[2], venn_anchors[3]) != false { os.exit(40) }
    if inside(venn_circles[0], venn_anchors[4]) != true || inside(venn_circles[1], venn_anchors[4]) != false || inside(venn_circles[2], venn_anchors[4]) != true { os.exit(41) }
    if inside(venn_circles[0], venn_anchors[5]) != false || inside(venn_circles[1], venn_anchors[5]) != true || inside(venn_circles[2], venn_anchors[5]) != true { os.exit(42) }
    if inside(venn_circles[0], venn_anchors[6]) != true || inside(venn_circles[1], venn_anchors[6]) != true || inside(venn_circles[2], venn_anchors[6]) != true { os.exit(43) }
    let (_, venn_room) = chart.venn3(venn_bounds, venn_circles[..], venn_anchors[..6usize], venn_layers[..])
    let (_, venn_flat) = chart.venn3(geometry.rect(0.0, 0.0, 0.0, 10.0), venn_circles[..], venn_anchors[..], venn_layers[..])
    if venn_room != chart.TooLarge || venn_flat != chart.Invalid { os.exit(44) }
    let cloud_words = [14]str{ "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo", "lima", "mike", "november" }
    let cloud_weights = [14]f32{ 3.0f32, 64.0f32, 62.0f32, 81.0f32, 54.0f32, 59.0f32, 81.0f32, 11.0f32, 28.0f32, 0.0f32, 71.0f32, 81.0f32, 8.0f32, 76.0f32 }
    let cloud_widths = [14]f32{ 3.68f32, 3.84f32, 5.34f32, 3.95f32, 5.43f32, 4.6f32, 3.25f32, 3.29f32, 5.39f32, 5.24f32, 3.16f32, 4.39f32, 4.52f32, 3.95f32 }
    let cloud_heights = [14]f32{ 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32, 1.0f32 }
    let cloud_excluded = [2]str{ "hotel", "mike" }
    let cloud_bounds = geometry.rect(0.0, 0.0, 640.0f32, 420.0f32)
    var cloud_order: [14]usize = zero
    var cloud_storage: [14]chart.CloudWord = zero
    let (cloud, cloud_error) = chart.word_cloud(cloud_words[..], cloud_weights[..], cloud_widths[..], cloud_heights[..], 0.8f32, cloud_excluded[..], cloud_bounds, 9.0f32, 36.0f32, 2.0f32, cloud_order[..], cloud_storage[..])
    if cloud_error != ok || cloud.len != 11usize { os.exit(45) }
    if !str.eq(cloud[0].label.text, "delta") || !str.eq(cloud[1].label.text, "golf") || !str.eq(cloud[2].label.text, "lima") || !str.eq(cloud[3].label.text, "november") || !str.eq(cloud[4].label.text, "kilo") || !str.eq(cloud[5].label.text, "bravo") || !str.eq(cloud[6].label.text, "charlie") || !str.eq(cloud[7].label.text, "foxtrot") || !str.eq(cloud[8].label.text, "echo") || !str.eq(cloud[9].label.text, "india") || !str.eq(cloud[10].label.text, "alpha") { os.exit(46) }
    if !close32(cloud[0].size, 36.0f32, 1e-5) || !close32(cloud[1].size, 36.0f32, 1e-5) || !close32(cloud[2].size, 36.0f32, 1e-5) || !close32(cloud[3].size, 34.871191548325385f32, 1e-5) || !close32(cloud[4].size, 33.704599092705436f32, 1e-5) || !close32(cloud[5].size, 32.0f32, 1e-5) || !close32(cloud[6].size, 31.496031496047245f32, 1e-5) || !close32(cloud[7].size, 30.72458299147443f32, 1e-5) || !close32(cloud[8].size, 29.393876913398138f32, 1e-5) || !close32(cloud[9].size, 21.166010488516726f32, 1e-5) || !close32(cloud[10].size, 9.0f32, 1e-5) { os.exit(47) }
    if !close32(cloud[0].box.width, 142.20000000000002f32, 1e-5) || !close32(cloud[0].box.height, 36.0f32, 1e-5) || !close32(cloud[1].box.width, 117.0f32, 1e-5) || !close32(cloud[1].box.height, 36.0f32, 1e-5) || !close32(cloud[2].box.width, 158.04f32, 1e-5) || !close32(cloud[2].box.height, 36.0f32, 1e-5) || !close32(cloud[3].box.width, 137.7412066158853f32, 1e-5) || !close32(cloud[3].box.height, 34.871191548325385f32, 1e-5) || !close32(cloud[4].box.width, 106.50653313294919f32, 1e-5) || !close32(cloud[4].box.height, 33.704599092705436f32, 1e-5) || !close32(cloud[5].box.width, 122.88f32, 1e-5) || !close32(cloud[5].box.height, 32.0f32, 1e-5) || !close32(cloud[6].box.width, 168.18880818889227f32, 1e-5) || !close32(cloud[6].box.height, 31.496031496047245f32, 1e-5) || !close32(cloud[7].box.width, 141.33308176078236f32, 1e-5) || !close32(cloud[7].box.height, 30.72458299147443f32, 1e-5) || !close32(cloud[8].box.width, 159.6087516397519f32, 1e-5) || !close32(cloud[8].box.height, 29.393876913398138f32, 1e-5) || !close32(cloud[9].box.width, 114.08479653310515f32, 1e-5) || !close32(cloud[9].box.height, 21.166010488516726f32, 1e-5) || !close32(cloud[10].box.width, 33.120000000000005f32, 1e-5) || !close32(cloud[10].box.height, 9.0f32, 1e-5) { os.exit(48) }
    if !close32(cloud[0].label.anchor.y - cloud[0].box.y, 28.8f32, 1e-4) || !close32(cloud[0].label.anchor.x, cloud[0].box.x, 1e-6) || !close32(cloud[1].label.anchor.y - cloud[1].box.y, 28.8f32, 1e-4) || !close32(cloud[1].label.anchor.x, cloud[1].box.x, 1e-6) || !close32(cloud[2].label.anchor.y - cloud[2].box.y, 28.8f32, 1e-4) || !close32(cloud[2].label.anchor.x, cloud[2].box.x, 1e-6) || !close32(cloud[3].label.anchor.y - cloud[3].box.y, 27.89695323866031f32, 1e-4) || !close32(cloud[3].label.anchor.x, cloud[3].box.x, 1e-6) || !close32(cloud[4].label.anchor.y - cloud[4].box.y, 26.96367927416435f32, 1e-4) || !close32(cloud[4].label.anchor.x, cloud[4].box.x, 1e-6) || !close32(cloud[5].label.anchor.y - cloud[5].box.y, 25.6f32, 1e-4) || !close32(cloud[5].label.anchor.x, cloud[5].box.x, 1e-6) || !close32(cloud[6].label.anchor.y - cloud[6].box.y, 25.196825196837796f32, 1e-4) || !close32(cloud[6].label.anchor.x, cloud[6].box.x, 1e-6) || !close32(cloud[7].label.anchor.y - cloud[7].box.y, 24.579666393179547f32, 1e-4) || !close32(cloud[7].label.anchor.x, cloud[7].box.x, 1e-6) || !close32(cloud[8].label.anchor.y - cloud[8].box.y, 23.51510153071851f32, 1e-4) || !close32(cloud[8].label.anchor.x, cloud[8].box.x, 1e-6) || !close32(cloud[9].label.anchor.y - cloud[9].box.y, 16.93280839081338f32, 1e-4) || !close32(cloud[9].label.anchor.x, cloud[9].box.x, 1e-6) || !close32(cloud[10].label.anchor.y - cloud[10].box.y, 7.2f32, 1e-4) || !close32(cloud[10].label.anchor.x, cloud[10].box.x, 1e-6) { os.exit(49) }
    if !cloud_contained(cloud, cloud_bounds) { os.exit(50) }
    if cloud_overlaps(cloud, 2.0f32) { os.exit(51) }
    if cloud_has(cloud, "hotel") || cloud_has(cloud, "mike") || cloud_has(cloud, "juliet") { os.exit(52) }
    if !close32(cloud[0].box.x + cloud[0].box.width * 0.5, 320.0f32, 1e-4) || !close32(cloud[0].box.y + cloud[0].box.height * 0.5, 210.0f32, 1e-4) { os.exit(53) }
    let dup_words = [2]str{ "same", "same" }
    let dup_weights = [2]f32{ 1.0, 2.0 }
    let dup_sizes = [2]f32{ 3.0, 3.0 }
    let (_, cloud_dup) = chart.word_cloud(dup_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let neg_weights = [2]f32{ 1.0, -2.0 }
    let two_words = [2]str{ "one", "two" }
    let (_, cloud_neg) = chart.word_cloud(two_words[..], neg_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let (_, cloud_len) = chart.word_cloud(two_words[..], dup_weights[..1usize], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let (_, cloud_range) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 40.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let (_, cloud_none) = chart.word_cloud(cloud_words[..0usize], cloud_weights[..0usize], cloud_widths[..0usize], cloud_heights[..0usize], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let all_out = [2]str{ "one", "two" }
    let (_, cloud_all) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, all_out[..], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    let (_, cloud_room) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..1usize], cloud_storage[..])
    let wide = [2]f32{ 30.0, 3.0 }
    let (_, cloud_wide) = chart.word_cloud(two_words[..], dup_weights[..], wide[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])
    if cloud_dup != chart.Invalid || cloud_neg != chart.Invalid || cloud_len != chart.Invalid || cloud_range != chart.Invalid || cloud_none != chart.Empty || cloud_all != chart.Empty || cloud_room != chart.TooLarge || cloud_wide != chart.TooLarge { os.exit(54) }
    try io.print("gfx chart composition reference ok\n")
    os.exit(0)
    ret ok
}
