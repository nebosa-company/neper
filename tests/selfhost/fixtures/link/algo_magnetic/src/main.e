// `e.algo.magnetic`: WMM2025 at fourteen places and dates against pygeomag (declination and inclination to 0.02
// degrees, intensities to 3 nT), and the tilt-compensated heading against orientations built from rotation
// matrices. Every check has its own exit code.
use e.os
use e.mem
use e.algo.magnetic as mag

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= tolerance
}

fn close_field(lat: f64, lon: f64, alt: f64, year: f64, d: f64, i: f64, h: f64, f: f64, x: f64, y: f64, z: f64) -> bool {
    let r = mag.field(lat, lon, alt, year)
    ret near(r.declination, d, 0.02f64) && near(r.inclination, i, 0.02f64) && near(r.horizontal, h, 3.0f64) && near(r.total, f, 3.0f64) && near(r.north, x, 3.0f64) && near(r.east, y, 3.0f64) && near(r.down, z, 3.0f64)
}

// The heading is the yaw: compared on the circle.
fn close_heading(mx: f64, my: f64, mz: f64, ax: f64, ay: f64, az: f64, yaw: f64) -> bool {
    let got = mag.heading(mx, my, mz, ax, ay, az)
    var d = got - yaw
    while d > 180.0f64 { d = d - 360.0f64 }
    while d < 0.0f64 - 180.0f64 { d = d + 360.0f64 }
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.05f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !close_field(47.6, -122.3, 0.05, 2026.78, 14.863209, 68.750053, 19062.504, 52595.334, 18424.692, 4889.765, 49019.283) { os.exit(1) }
    if !close_field(59.9, 10.7, 0.02, 2027.5, 5.182321, 72.939981, 15143.742, 51619.358, 15081.839, 1367.863, 49348.001) { os.exit(2) }
    if !close_field(30.0, 31.2, 0.0, 2025.0, 4.721529, 44.845916, 31152.298, 43938.001, 31046.584, 2564.239, 30985.194) { os.exit(3) }
    if !close_field(-33.9, 151.2, 0.0, 2029.0, 12.884323, -64.430544, 24582.554, 56956.149, 23963.621, 5481.501, -51378.020) { os.exit(4) }
    if !close_field(64.1, -21.9, 0.0, 2026.0, -11.245084, 75.400319, 13249.947, 52565.811, 12995.575, -2583.821, 50868.491) { os.exit(5) }
    if !close_field(-0.2, -78.5, 2.8, 2028.25, -5.348650, 19.717719, 26407.351, 28052.154, 26292.371, -2461.588, 9464.415) { os.exit(6) }
    if !close_field(35.7, 139.7, 0.04, 2026.9, -7.945998, 49.571868, 30413.756, 46899.074, 30121.747, -4204.388, 35700.513) { os.exit(7) }
    if !close_field(-33.9, 18.4, 0.0, 2025.5, -26.472328, -64.789329, 10665.586, 25039.655, 9547.297, -4754.351, -22654.571) { os.exit(8) }
    if !close_field(19.1, 72.9, 0.0, 2027.0, -0.004608, 28.378970, 38364.600, 43604.902, 38364.600, -3.085, 20725.467) { os.exit(9) }
    if !close_field(-22.9, -43.2, 0.0, 2029.9, -23.070890, -44.289905, 16522.225, 23081.672, 15200.789, -6474.560, -16117.682) { os.exit(10) }
    if !close_field(61.2, -149.9, 0.0, 2026.5, 14.061423, 73.941902, 15193.669, 54927.742, 14738.403, 3691.483, 52784.555) { os.exit(11) }
    if !close_field(-60.0, -60.0, 0.0, 2025.0, 9.627165, -54.494177, 19318.172, 33262.136, 19046.112, 3230.698, -27077.258) { os.exit(12) }
    if !close_field(0.0, 0.0, 0.0, 2027.0, -3.769368, -30.198901, 27472.547, 31786.465, 27413.118, -1806.057, -15988.699) { os.exit(13) }
    if !close_field(89.0, 45.0, 0.0, 2026.0, 55.059040, 87.847082, 2136.943, 56884.012, 1223.896, 1751.743, 56843.859) { os.exit(14) }
    if !close_heading(18316.7018, -10575.1527, 47504.3638, 0.00000, 0.00000, 9.81000, 30.0000) { os.exit(15) }
    if !close_heading(-34923.6390, -2806.8667, 38424.7438, -3.35522, -2.38589, 8.90428, 200.0000) { os.exit(16) }
    if !close_heading(38383.8821, 32412.1258, 13421.3149, 5.62678, 5.16537, 6.15584, 310.0000) { os.exit(17) }
    if !close_heading(16928.7418, 4101.3108, 48995.8871, -0.85500, 0.85174, 9.73548, 0.5000) { os.exit(18) }
    if !close_heading(-41139.9858, -16704.4617, 27064.0449, -8.49571, 0.85174, 4.83048, 90.0000) { os.exit(19) }
    if !close_heading(-12576.7662, 49752.3940, 8397.8714, 1.70349, 9.51419, 1.67761, 181.0000) { os.exit(20) }
    let hx: [7]f64 = [7]f64{ 52.000f64, -28.000f64, 12.000f64, 12.000f64, 12.000f64, 12.000f64, 36.000f64 }
    let hy: [7]f64 = [7]f64{ -7.000f64, -7.000f64, 33.000f64, -47.000f64, -7.000f64, -7.000f64, 17.000f64 }
    let hz: [7]f64 = [7]f64{ 3.000f64, 3.000f64, 3.000f64, 3.000f64, 43.000f64, -37.000f64, 23.000f64 }
    let (ox, oy, oz) = mag.calibrate_hard_iron(hx[0usize..7usize], hy[0usize..7usize], hz[0usize..7usize], 7usize)
    if !near(ox, 12.0f64, 0.001f64) || !near(oy, -7.0f64, 0.001f64) || !near(oz, 3.0f64, 0.001f64) { os.exit(21) }
    ret ok
}
