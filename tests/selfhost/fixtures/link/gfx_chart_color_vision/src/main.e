use e.gfx.chart
use e.gfx.paint
use e.io
use e.mem

// References: scripts/chart_cvd_reference.py (numpy for the simulation, scikit-image
// for CIELAB and CIEDE2000), and Sharma, Wu and Dalal (2005) pairs 1, 2, 7, 14.
fn near(value: f64, expected: f64, tolerance: f64) -> bool { ret value - expected <= tolerance && expected - value <= tolerance }

fn seen(color: paint.Color, vision: chart.ColorVision, severity: f32, r: f64, g: f64, b: f64) -> bool {
    let (out, out_error) = chart.simulate_color_vision(color, vision, severity)
    ret out_error == ok && near(f64(out.red), r, 0.0002f64) && near(f64(out.green), g, 0.0002f64) && near(f64(out.blue), b, 0.0002f64) && out.alpha == color.alpha
}

fn byte_color(r: f32, g: f32, b: f32) -> paint.Color { ret paint.rgba(r / 255.0, g / 255.0, b / 255.0, 1.0) }

fn separated(colors: []const paint.Color, vision: chart.ColorVision, expected: f64, first: usize, second: usize) -> bool {
    let (pair, pair_error) = chart.palette_separation(colors, vision, 1.0)
    ret pair_error == ok && near(pair.difference, expected, 0.02f64) && pair.first == first && pair.second == second
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pairs = [10]chart.Lab{
        chart.Lab { l: 50.0f64, a: 2.6772f64, b: -79.7751f64 }, chart.Lab { l: 50.0f64, a: 0.0f64, b: -82.7485f64 },
        chart.Lab { l: 50.0f64, a: 3.1571f64, b: -77.2803f64 }, chart.Lab { l: 50.0f64, a: 0.0f64, b: -82.7485f64 },
        chart.Lab { l: 50.0f64, a: -1.3802f64, b: -84.2814f64 }, chart.Lab { l: 50.0f64, a: 0.0f64, b: -82.7485f64 },
        chart.Lab { l: 60.2574f64, a: -34.0099f64, b: 36.2677f64 }, chart.Lab { l: 60.4626f64, a: -34.1751f64, b: 39.4387f64 },
        chart.Lab { l: 50.0f64, a: 2.5f64, b: 0.0f64 }, chart.Lab { l: 73.0f64, a: 25.0f64, b: -18.0f64 },
    }
    let expected = [5]f64{ 2.042459680f64, 2.861510175f64, 0.999998865f64, 1.264420014f64, 27.149231301f64 }
    var i = 0usize
    while i < 5usize {
        let forward = chart.ciede2000(pairs[2usize * i], pairs[2usize * i + 1usize])
        let backward = chart.ciede2000(pairs[2usize * i + 1usize], pairs[2usize * i])
        if !near(forward, expected[i], 0.0001f64) || !near(backward, forward, 0.000000001f64) { ret chart.Invalid }
        i += 1usize
    }
    let red = paint.rgba(1.0, 0.0, 0.0, 1.0)
    let (red_lab, red_error) = chart.color_lab(red)
    let (white_lab, white_error) = chart.color_lab(paint.rgba(1.0, 1.0, 1.0, 1.0))
    if red_error != ok || white_error != ok || !near(red_lab.l, 53.2406f64, 0.01f64) || !near(red_lab.a, 80.0923f64, 0.01f64) || !near(red_lab.b, 67.2028f64, 0.01f64) { ret chart.Invalid }
    if !near(white_lab.l, 100.0f64, 0.01f64) || !near(white_lab.a, 0.0f64, 0.01f64) || !near(white_lab.b, 0.0f64, 0.01f64) { ret chart.Invalid }
    if !seen(red, .Protan, 1.0, 0.369337f64, 0.369337f64, 0.050772f64) || !seen(red, .Deutan, 1.0, 0.577353f64, 0.577353f64, 0.0f64) { ret chart.Invalid }
    if !seen(paint.rgba(0.0, 0.0, 1.0, 1.0), .Tritan, 1.0, 0.0f64, 0.411077f64, 0.411077f64) || !seen(paint.rgba(0.8, 0.3, 0.2, 0.5), .Deutan, 0.5, 0.677196f64, 0.424782f64, 0.179882f64) { ret chart.Invalid }
    // White and grey sit on every confusion plane; typical vision and zero severity are identities.
    if !seen(paint.rgba(1.0, 1.0, 1.0, 1.0), .Protan, 1.0, 1.0f64, 1.0f64, 1.0f64) || !seen(red, .Typical, 1.0, 1.0f64, 0.0f64, 0.0f64) || !seen(red, .Tritan, 0.0, 1.0f64, 0.0f64, 0.0f64) { ret chart.Invalid }
    // The accessible palette on white keeps hue separation for typical vision
    // but not for deuteranopes: blue and purple nearly coincide.
    let palette = [6]paint.Color{ byte_color(0.0, 114.0, 178.0), byte_color(195.0, 86.0, 0.0), byte_color(0.0, 135.0, 99.0), byte_color(142.0, 68.0, 173.0), byte_color(179.0, 38.0, 62.0), byte_color(171.0, 102.0, 0.0) }
    if !separated(palette[..], .Typical, 10.0052f64, 1usize, 5usize) || !separated(palette[..], .Protan, 2.5898f64, 1usize, 5usize) { ret chart.Invalid }
    if !separated(palette[..], .Deutan, 1.2196f64, 0usize, 3usize) || !separated(palette[..], .Tritan, 2.4452f64, 0usize, 2usize) { ret chart.Invalid }
    let (_, high_error) = chart.simulate_color_vision(red, .Protan, 1.5)
    let (_, low_error) = chart.simulate_color_vision(red, .Protan, -0.1)
    let zero_f: f32 = 0.0
    let nan = zero_f / zero_f
    let (_, nan_error) = chart.simulate_color_vision(red, .Deutan, nan)
    let (_, color_error) = chart.simulate_color_vision(paint.rgba(1.2, 0.0, 0.0, 1.0), .Deutan, 1.0)
    let (_, lab_error) = chart.color_lab(paint.rgba(0.0, -0.1, 0.0, 1.0))
    let (_, single_error) = chart.palette_separation(palette[..1usize], .Typical, 1.0)
    if high_error != chart.Invalid || low_error != chart.Invalid || nan_error != chart.Invalid || color_error != chart.Invalid || lab_error != chart.Invalid || single_error != chart.Empty { ret chart.Invalid }
    try io.print("gfx chart color vision ok\n")
    ret ok
}
