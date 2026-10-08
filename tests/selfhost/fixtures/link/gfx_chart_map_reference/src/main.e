// The maps of e.gfx.chart against independent references (L070, D2254;
// scripts/chart_map_reference.py writes this file): the equirectangular and Mercator projections on three
// windows, one centred on the antimeridian; area-scaled proportional symbols; choropleth normalisation,
// missing regions and ring winding from a shoelace sum; and the refusals of the projection and of both
// layers, with each storage array one element short. Every check has its own exit code.
use e.algo.geo
use e.gfx.chart
use e.gfx.geometry
use e.mem
use e.os

fn zero_f64() -> f64 {
    ret 0.0f64
}

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn area_ratio(big: geometry.Rect, small: geometry.Rect) -> f64 {
    ret (f64(big.width) * f64(big.height)) / (f64(small.width) * f64(small.height))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let w_equi = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 180.0f64, south_lat: -60.0f64, north_lat: 70.0f64 }
    let w_seam = geo.MapWindow { projection: .Equirectangular, center_lon: 180.0f64, half_lon_span: 30.0f64, south_lat: -10.0f64, north_lat: 20.0f64 }
    let w_merc = geo.MapWindow { projection: .Mercator, center_lon: 10.0f64, half_lon_span: 100.0f64, south_lat: -70.0f64, north_lat: 75.0f64 }
    let bounds = geometry.rect(20.0, 30.0, 200.0, 160.0)
    let (px_w_equi_0, py_w_equi_0, pe_w_equi_0) = geo.map_project(-179.9f64, 69.9f64, w_equi)
    if pe_w_equi_0 != ok || abs64(px_w_equi_0 - 0.000277777777777762f64) > 1e-12f64 || abs64(py_w_equi_0 - 0.0007692307692307255f64) > 1e-12f64 { os.exit(1) }
    let (px_w_equi_1, py_w_equi_1, pe_w_equi_1) = geo.map_project(0.0f64, 0.0f64, w_equi)
    if pe_w_equi_1 != ok || abs64(px_w_equi_1 - 0.5f64) > 1e-12f64 || abs64(py_w_equi_1 - 0.5384615384615384f64) > 1e-12f64 { os.exit(2) }
    let (px_w_equi_2, py_w_equi_2, pe_w_equi_2) = geo.map_project(45.5f64, -59.9f64, w_equi)
    if pe_w_equi_2 != ok || abs64(px_w_equi_2 - 0.6263888888888889f64) > 1e-12f64 || abs64(py_w_equi_2 - 0.9992307692307693f64) > 1e-12f64 { os.exit(3) }
    let (px_w_equi_3, py_w_equi_3, pe_w_equi_3) = geo.map_project(179.9f64, 10.0f64, w_equi)
    if pe_w_equi_3 != ok || abs64(px_w_equi_3 - 0.9997222222222222f64) > 1e-12f64 || abs64(py_w_equi_3 - 0.46153846153846156f64) > 1e-12f64 { os.exit(4) }
    let (px_w_equi_4, py_w_equi_4, pe_w_equi_4) = geo.map_project(-90.0f64, 35.25f64, w_equi)
    if pe_w_equi_4 != ok || abs64(px_w_equi_4 - 0.25f64) > 1e-12f64 || abs64(py_w_equi_4 - 0.2673076923076923f64) > 1e-12f64 { os.exit(5) }
    let (px_w_equi_5, py_w_equi_5, pe_w_equi_5) = geo.map_project(12.3456f64, -12.3456f64, w_equi)
    if pe_w_equi_5 != ok || abs64(px_w_equi_5 - 0.5342933333333333f64) > 1e-12f64 || abs64(py_w_equi_5 - 0.6334276923076924f64) > 1e-12f64 { os.exit(6) }
    let (px_w_equi_6, py_w_equi_6, pe_w_equi_6) = geo.map_project(-0.001f64, 69.999f64, w_equi)
    if pe_w_equi_6 != ok || abs64(px_w_equi_6 - 0.4999972222222222f64) > 1e-12f64 || abs64(py_w_equi_6 - 7.692307692344423e-06f64) > 1e-12f64 { os.exit(7) }
    let (px_w_seam_0, py_w_seam_0, pe_w_seam_0) = geo.map_project(170.0f64, 5.0f64, w_seam)
    if pe_w_seam_0 != ok || abs64(px_w_seam_0 - 0.3333333333333333f64) > 1e-12f64 || abs64(py_w_seam_0 - 0.5f64) > 1e-12f64 { os.exit(8) }
    let (px_w_seam_1, py_w_seam_1, pe_w_seam_1) = geo.map_project(-170.0f64, -9.5f64, w_seam)
    if pe_w_seam_1 != ok || abs64(px_w_seam_1 - 0.6666666666666666f64) > 1e-12f64 || abs64(py_w_seam_1 - 0.9833333333333333f64) > 1e-12f64 { os.exit(9) }
    let (px_w_seam_2, py_w_seam_2, pe_w_seam_2) = geo.map_project(180.0f64, 0.0f64, w_seam)
    if pe_w_seam_2 != ok || abs64(px_w_seam_2 - 0.5f64) > 1e-12f64 || abs64(py_w_seam_2 - 0.6666666666666666f64) > 1e-12f64 { os.exit(10) }
    let (px_w_seam_3, py_w_seam_3, pe_w_seam_3) = geo.map_project(-180.0f64, 19.0f64, w_seam)
    if pe_w_seam_3 != ok || abs64(px_w_seam_3 - 0.5f64) > 1e-12f64 || abs64(py_w_seam_3 - 0.03333333333333333f64) > 1e-12f64 { os.exit(11) }
    let (px_w_seam_4, py_w_seam_4, pe_w_seam_4) = geo.map_project(160.0f64, 10.0f64, w_seam)
    if pe_w_seam_4 != ok || abs64(px_w_seam_4 - 0.16666666666666666f64) > 1e-12f64 || abs64(py_w_seam_4 - 0.3333333333333333f64) > 1e-12f64 { os.exit(12) }
    let (px_w_seam_5, py_w_seam_5, pe_w_seam_5) = geo.map_project(-160.0f64, 0.5f64, w_seam)
    if pe_w_seam_5 != ok || abs64(px_w_seam_5 - 0.8333333333333334f64) > 1e-12f64 || abs64(py_w_seam_5 - 0.65f64) > 1e-12f64 { os.exit(13) }
    let (px_w_seam_6, py_w_seam_6, pe_w_seam_6) = geo.map_project(179.5f64, 19.9f64, w_seam)
    if pe_w_seam_6 != ok || abs64(px_w_seam_6 - 0.49166666666666664f64) > 1e-12f64 || abs64(py_w_seam_6 - 0.003333333333333381f64) > 1e-12f64 { os.exit(14) }
    let (px_w_merc_0, py_w_merc_0, pe_w_merc_0) = geo.map_project(10.0f64, 0.0f64, w_merc)
    if pe_w_merc_0 != ok || abs64(px_w_merc_0 - 0.5f64) > 1e-12f64 || abs64(py_w_merc_0 - 0.538821937705992f64) > 1e-12f64 { os.exit(15) }
    let (px_w_merc_1, py_w_merc_1, pe_w_merc_1) = geo.map_project(-89.9f64, 74.9f64, w_merc)
    if pe_w_merc_1 != ok || abs64(px_w_merc_1 - 0.0004999999999999716f64) > 1e-12f64 || abs64(py_w_merc_1 - 0.0017862243693292416f64) > 1e-12f64 { os.exit(16) }
    let (px_w_merc_2, py_w_merc_2, pe_w_merc_2) = geo.map_project(109.9f64, -69.9f64, w_merc)
    if pe_w_merc_2 != ok || abs64(px_w_merc_2 - 0.9995f64) > 1e-12f64 || abs64(py_w_merc_2 - 0.9986471428108349f64) > 1e-12f64 { os.exit(17) }
    let (px_w_merc_3, py_w_merc_3, pe_w_merc_3) = geo.map_project(45.0f64, 45.0f64, w_merc)
    if pe_w_merc_3 != ok || abs64(px_w_merc_3 - 0.675f64) > 1e-12f64 || abs64(py_w_merc_3 - 0.3046012326190998f64) > 1e-12f64 { os.exit(18) }
    let (px_w_merc_4, py_w_merc_4, pe_w_merc_4) = geo.map_project(60.0f64, 60.0f64, w_merc)
    if pe_w_merc_4 != ok || abs64(px_w_merc_4 - 0.75f64) > 1e-12f64 || abs64(py_w_merc_4 - 0.1888468400512428f64) > 1e-12f64 { os.exit(19) }
    let (px_w_merc_5, py_w_merc_5, pe_w_merc_5) = geo.map_project(-30.0f64, -30.0f64, w_merc)
    if pe_w_merc_5 != ok || abs64(px_w_merc_5 - 0.3f64) > 1e-12f64 || abs64(py_w_merc_5 - 0.6847973496417614f64) > 1e-12f64 { os.exit(20) }
    let (px_w_merc_6, py_w_merc_6, pe_w_merc_6) = geo.map_project(10.0f64, 74.99f64, w_merc)
    if pe_w_merc_6 != ok || abs64(px_w_merc_6 - 0.5f64) > 1e-12f64 || abs64(py_w_merc_6 - 0.00017914512232326775f64) > 1e-12f64 { os.exit(21) }
    let nan = 0.0f64 / zero_f64()
    let infinity = 1.0f64 / zero_f64()
    let (_rx_lon_high, _ry_lon_high, re_lon_high) = geo.map_project(180.5f64, 0.0f64, w_equi)
    if re_lon_high != geo.Invalid { os.exit(22) }
    let (_rx_lon_low, _ry_lon_low, re_lon_low) = geo.map_project(-180.5f64, 0.0f64, w_equi)
    if re_lon_low != geo.Invalid { os.exit(23) }
    let (_rx_lat_north, _ry_lat_north, re_lat_north) = geo.map_project(0.0f64, 70.5f64, w_equi)
    if re_lat_north != geo.Invalid { os.exit(24) }
    let (_rx_lat_south, _ry_lat_south, re_lat_south) = geo.map_project(0.0f64, -60.5f64, w_equi)
    if re_lat_south != geo.Invalid { os.exit(25) }
    let (_rx_beyond_span, _ry_beyond_span, re_beyond_span) = geo.map_project(100.0f64, 0.0f64, w_seam)
    if re_beyond_span != geo.Invalid { os.exit(26) }
    let (_rx_lon_nan, _ry_lon_nan, re_lon_nan) = geo.map_project(nan, 0.0f64, w_equi)
    if re_lon_nan != geo.Invalid { os.exit(27) }
    let (_rx_lat_nan, _ry_lat_nan, re_lat_nan) = geo.map_project(0.0f64, nan, w_equi)
    if re_lat_nan != geo.Invalid { os.exit(28) }
    let (_rx_lon_inf, _ry_lon_inf, re_lon_inf) = geo.map_project(infinity, 0.0f64, w_equi)
    if re_lon_inf != geo.Invalid { os.exit(29) }
    let (_rx_lat_inf, _ry_lat_inf, re_lat_inf) = geo.map_project(0.0f64, 0.0f64 - infinity, w_equi)
    if re_lat_inf != geo.Invalid { os.exit(30) }
    let bad_span_zero = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 0.0f64, south_lat: -10.0f64, north_lat: 10.0f64 }
    let (_wx_span_zero, _wy_span_zero, we_span_zero) = geo.map_project(0.0f64, 0.0f64, bad_span_zero)
    if we_span_zero != geo.Invalid { os.exit(31) }
    let bad_span_wide = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 181.0f64, south_lat: -10.0f64, north_lat: 10.0f64 }
    let (_wx_span_wide, _wy_span_wide, we_span_wide) = geo.map_project(0.0f64, 0.0f64, bad_span_wide)
    if we_span_wide != geo.Invalid { os.exit(32) }
    let bad_center_high = geo.MapWindow { projection: .Equirectangular, center_lon: 181.0f64, half_lon_span: 10.0f64, south_lat: -10.0f64, north_lat: 10.0f64 }
    let (_wx_center_high, _wy_center_high, we_center_high) = geo.map_project(0.0f64, 0.0f64, bad_center_high)
    if we_center_high != geo.Invalid { os.exit(33) }
    let bad_flat = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: 5.0f64, north_lat: 5.0f64 }
    let (_wx_flat, _wy_flat, we_flat) = geo.map_project(0.0f64, 0.0f64, bad_flat)
    if we_flat != geo.Invalid { os.exit(34) }
    let bad_inverted = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: 10.0f64, north_lat: -10.0f64 }
    let (_wx_inverted, _wy_inverted, we_inverted) = geo.map_project(0.0f64, 0.0f64, bad_inverted)
    if we_inverted != geo.Invalid { os.exit(35) }
    let bad_south_pole = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: -91.0f64, north_lat: 10.0f64 }
    let (_wx_south_pole, _wy_south_pole, we_south_pole) = geo.map_project(0.0f64, 0.0f64, bad_south_pole)
    if we_south_pole != geo.Invalid { os.exit(36) }
    let bad_merc_north = geo.MapWindow { projection: .Mercator, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: -10.0f64, north_lat: 85.5f64 }
    let (_wx_merc_north, _wy_merc_north, we_merc_north) = geo.map_project(0.0f64, 0.0f64, bad_merc_north)
    if we_merc_north != geo.Invalid { os.exit(37) }
    let bad_merc_south = geo.MapWindow { projection: .Mercator, center_lon: 0.0f64, half_lon_span: 10.0f64, south_lat: -85.5f64, north_lat: 10.0f64 }
    let (_wx_merc_south, _wy_merc_south, we_merc_south) = geo.map_project(0.0f64, 0.0f64, bad_merc_south)
    if we_merc_south != geo.Invalid { os.exit(38) }
    let sites = [6]chart.MapSite{ chart.MapSite { key: "S0", lon: -120.0f64, lat: 50.0f64, value: 100.0f64, present: true }, chart.MapSite { key: "S1", lon: -60.0f64, lat: 20.0f64, value: 25.0f64, present: true }, chart.MapSite { key: "S2", lon: 0.0f64, lat: 0.0f64, value: 4.0f64, present: true }, chart.MapSite { key: "S3", lon: 30.0f64, lat: -30.0f64, value: 1.0f64, present: true }, chart.MapSite { key: "S4", lon: 90.0f64, lat: 40.0f64, value: 0.25f64, present: true }, chart.MapSite { key: "S5", lon: 150.0f64, lat: 60.0f64, value: 0.0f64, present: true } }
    var circles: [6]geometry.Rect = zero
    let (symbols, symbols_error) = chart.proportional_symbol_map(sites[..], w_equi, bounds, 12.5f32, circles[..])
    if symbols_error != ok || symbols.present_count != 6usize || symbols.maximum != 100.0f64 { os.exit(39) }
    if abs64(f64(circles[0usize].width) - 25.0f64) > 1e-4f64 || abs64(f64(circles[0usize].height) - 25.0f64) > 1e-4f64 || abs64(f64(circles[0usize].x) + f64(circles[0usize].width) * 0.5f64 - 53.33333432674408f64) > 1e-3f64 || abs64(f64(circles[0usize].y) + f64(circles[0usize].height) * 0.5f64 - 54.61538553237915f64) > 1e-3f64 { os.exit(40) }
    if abs64(f64(circles[1usize].width) - 12.5f64) > 1e-4f64 || abs64(f64(circles[1usize].height) - 12.5f64) > 1e-4f64 || abs64(f64(circles[1usize].x) + f64(circles[1usize].width) * 0.5f64 - 86.66666865348816f64) > 1e-3f64 || abs64(f64(circles[1usize].y) + f64(circles[1usize].height) * 0.5f64 - 91.53846263885498f64) > 1e-3f64 { os.exit(41) }
    if abs64(f64(circles[2usize].width) - 5.0f64) > 1e-4f64 || abs64(f64(circles[2usize].height) - 5.0f64) > 1e-4f64 || abs64(f64(circles[2usize].x) + f64(circles[2usize].width) * 0.5f64 - 120.0f64) > 1e-3f64 || abs64(f64(circles[2usize].y) + f64(circles[2usize].height) * 0.5f64 - 116.15385055541992f64) > 1e-3f64 { os.exit(42) }
    if abs64(f64(circles[3usize].width) - 2.5f64) > 1e-4f64 || abs64(f64(circles[3usize].height) - 2.5f64) > 1e-4f64 || abs64(f64(circles[3usize].x) + f64(circles[3usize].width) * 0.5f64 - 136.66666269302368f64) > 1e-3f64 || abs64(f64(circles[3usize].y) + f64(circles[3usize].height) * 0.5f64 - 153.07692527770996f64) > 1e-3f64 { os.exit(43) }
    if abs64(f64(circles[4usize].width) - 1.25f64) > 1e-4f64 || abs64(f64(circles[4usize].height) - 1.25f64) > 1e-4f64 || abs64(f64(circles[4usize].x) + f64(circles[4usize].width) * 0.5f64 - 170.0f64) > 1e-3f64 || abs64(f64(circles[4usize].y) + f64(circles[4usize].height) * 0.5f64 - 66.92307710647583f64) > 1e-3f64 { os.exit(44) }
    if circles[5usize].width != 0.0f32 || circles[5usize].height != 0.0f32 { os.exit(45) }
    if abs64(area_ratio(circles[0usize], circles[1usize]) - 4.0f64) > 1e-3f64 || abs64(area_ratio(circles[0usize], circles[2usize]) - 25.0f64) > 1e-2f64 || abs64(area_ratio(circles[0usize], circles[3usize]) - 100.0f64) > 1e-1f64 { os.exit(46) }
    var absent = sites
    absent[0] = chart.MapSite { key: "S0", lon: -120.0f64, lat: 50.0f64, value: 1000.0f64, present: false }
    let (absent_map, absent_error) = chart.proportional_symbol_map(absent[..], w_equi, bounds, 12.5f32, circles[..])
    if absent_error != ok || absent_map.present_count != 5usize || absent_map.maximum != 25.0f64 || circles[0usize].width != 0.0f32 { os.exit(47) }
    var bad_value = sites
    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 20.0f64, value: -1.0f64, present: true }
    let (_sa, e_negative) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])
    if e_negative != chart.Invalid { os.exit(48) }
    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 20.0f64, value: nan, present: true }
    let (_sb, e_value_nan) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])
    if e_value_nan != chart.Invalid { os.exit(49) }
    bad_value[1] = chart.MapSite { key: "", lon: -60.0f64, lat: 20.0f64, value: 1.0f64, present: true }
    let (_sc, e_key) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])
    if e_key != chart.Invalid { os.exit(50) }
    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 80.0f64, value: 1.0f64, present: true }
    let (_sd, e_outside) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])
    if e_outside != chart.Invalid { os.exit(51) }
    let (_se, e_radius_zero) = chart.proportional_symbol_map(sites[..], w_equi, bounds, 0.0f32, circles[..])
    if e_radius_zero != chart.Invalid { os.exit(52) }
    let (_sf, e_radius_nan) = chart.proportional_symbol_map(sites[..], w_equi, bounds, f32(nan), circles[..])
    if e_radius_nan != chart.Invalid { os.exit(53) }
    let (_sg, e_empty) = chart.proportional_symbol_map(sites[..0usize], w_equi, bounds, 12.5f32, circles[..])
    if e_empty != chart.Invalid { os.exit(54) }
    let (_sh, e_short) = chart.proportional_symbol_map(sites[..], w_equi, bounds, 12.5f32, circles[..5usize])
    if e_short != chart.TooLarge { os.exit(55) }
    let (_si, e_bounds) = chart.proportional_symbol_map(sites[..], w_equi, geometry.rect(0.0, 0.0, 0.0, 10.0), 12.5f32, circles[..])
    if e_bounds != chart.Invalid { os.exit(56) }
    let regions = [5]chart.MapRegion{ chart.MapRegion { key: "A" }, chart.MapRegion { key: "B" }, chart.MapRegion { key: "C" }, chart.MapRegion { key: "D" }, chart.MapRegion { key: "E" } }
    let rings = [7]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: false }, chart.MapRing { region: 0usize, first: 4usize, count: 4usize, hole: true }, chart.MapRing { region: 1usize, first: 8usize, count: 4usize, hole: false }, chart.MapRing { region: 1usize, first: 12usize, count: 4usize, hole: true }, chart.MapRing { region: 2usize, first: 16usize, count: 4usize, hole: false }, chart.MapRing { region: 3usize, first: 20usize, count: 4usize, hole: false }, chart.MapRing { region: 4usize, first: 24usize, count: 4usize, hole: false } }
    let vertices = [28]chart.MapVertex{ chart.MapVertex { lon: -100.0f64, lat: 10.0f64 }, chart.MapVertex { lon: -80.0f64, lat: 10.0f64 }, chart.MapVertex { lon: -80.0f64, lat: 30.0f64 }, chart.MapVertex { lon: -100.0f64, lat: 30.0f64 }, chart.MapVertex { lon: -90.0f64, lat: 25.0f64 }, chart.MapVertex { lon: -85.0f64, lat: 25.0f64 }, chart.MapVertex { lon: -85.0f64, lat: 20.0f64 }, chart.MapVertex { lon: -90.0f64, lat: 20.0f64 }, chart.MapVertex { lon: -50.0f64, lat: 0.0f64 }, chart.MapVertex { lon: -30.0f64, lat: 0.0f64 }, chart.MapVertex { lon: -30.0f64, lat: -20.0f64 }, chart.MapVertex { lon: -50.0f64, lat: -20.0f64 }, chart.MapVertex { lon: -45.0f64, lat: -15.0f64 }, chart.MapVertex { lon: -40.0f64, lat: -15.0f64 }, chart.MapVertex { lon: -40.0f64, lat: -10.0f64 }, chart.MapVertex { lon: -45.0f64, lat: -10.0f64 }, chart.MapVertex { lon: 10.0f64, lat: 30.0f64 }, chart.MapVertex { lon: 25.0f64, lat: 30.0f64 }, chart.MapVertex { lon: 25.0f64, lat: 45.0f64 }, chart.MapVertex { lon: 10.0f64, lat: 45.0f64 }, chart.MapVertex { lon: 60.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 70.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 70.0f64, lat: 10.0f64 }, chart.MapVertex { lon: 60.0f64, lat: 10.0f64 }, chart.MapVertex { lon: 100.0f64, lat: 50.0f64 }, chart.MapVertex { lon: 110.0f64, lat: 50.0f64 }, chart.MapVertex { lon: 110.0f64, lat: 40.0f64 }, chart.MapVertex { lon: 100.0f64, lat: 40.0f64 } }
    let metrics = [4]chart.MapMetric{ chart.MapMetric { key: "A", value: -5.0f64 }, chart.MapMetric { key: "B", value: 15.0f64 }, chart.MapMetric { key: "C", value: 5.0f64 }, chart.MapMetric { key: "Z", value: 1000.0f64 } }
    var c_points: [28]chart.Coord = zero
    var c_rings: [7]chart.MapProjectedRing = zero
    var c_regions: [5]chart.MapRegionLayout = zero
    var work = chart.ChoroplethStorage { points: c_points[..], rings: c_rings[..], regions: c_regions[..] }
    let (map, map_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)
    if map_error != ok || map.regions.len != 5usize || !map.has_values || map.minimum != -5.0f64 || map.maximum != 15.0f64 { os.exit(57) }
    if !map.regions[0usize].has_value || abs64(f64(map.regions[0usize].fraction) - 0.0f64) > 1e-6f64 { os.exit(58) }
    if !map.regions[1usize].has_value || abs64(f64(map.regions[1usize].fraction) - 1.0f64) > 1e-6f64 { os.exit(59) }
    if !map.regions[2usize].has_value || abs64(f64(map.regions[2usize].fraction) - 0.5f64) > 1e-6f64 { os.exit(60) }
    if map.regions[3usize].has_value || map.regions[4usize].has_value || map.regions[3usize].fraction != 0.0f32 || map.regions[4usize].fraction != 0.0f32 { os.exit(61) }
    let want_reverse = [7]bool{ true, true, false, false, true, true, false }
    var winding_ok = true
    var wi = 0usize
    while wi < 7usize {
        if work.rings[wi].reverse != want_reverse[wi] { winding_ok = false }
        wi += 1usize
    }
    if !winding_ok { os.exit(62) }
    let equal_metrics = [2]chart.MapMetric{ chart.MapMetric { key: "A", value: 7.0f64 }, chart.MapMetric { key: "B", value: 7.0f64 } }
    let (equal_map, equal_error) = chart.choropleth(regions[..], rings[..], vertices[..], equal_metrics[..], w_equi, bounds, &work)
    if equal_error != ok || equal_map.regions[0usize].fraction != 0.5f32 || equal_map.regions[1usize].fraction != 0.5f32 { os.exit(63) }
    let (none_map, none_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..0usize], w_equi, bounds, &work)
    if none_error != ok || none_map.has_values || none_map.regions[0usize].has_value { os.exit(64) }
    let dup_regions = [5]chart.MapRegion{ chart.MapRegion { key: "A" }, chart.MapRegion { key: "A" }, chart.MapRegion { key: "C" }, chart.MapRegion { key: "D" }, chart.MapRegion { key: "E" } }
    let (_ca, e_dup_region) = chart.choropleth(dup_regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)
    if e_dup_region != chart.Invalid { os.exit(65) }
    let blank_regions = [5]chart.MapRegion{ chart.MapRegion { key: "" }, chart.MapRegion { key: "B" }, chart.MapRegion { key: "C" }, chart.MapRegion { key: "D" }, chart.MapRegion { key: "E" } }
    let (_cb, e_blank_region) = chart.choropleth(blank_regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)
    if e_blank_region != chart.Invalid { os.exit(66) }
    let nan_metrics = [1]chart.MapMetric{ chart.MapMetric { key: "A", value: nan } }
    let (_cc, e_nan_metric) = chart.choropleth(regions[..], rings[..], vertices[..], nan_metrics[..], w_equi, bounds, &work)
    if e_nan_metric != chart.Invalid { os.exit(67) }
    let dup_metrics = [2]chart.MapMetric{ chart.MapMetric { key: "A", value: 1.0f64 }, chart.MapMetric { key: "A", value: 2.0f64 } }
    let (_cd, e_dup_metric) = chart.choropleth(regions[..], rings[..], vertices[..], dup_metrics[..], w_equi, bounds, &work)
    if e_dup_metric != chart.Invalid { os.exit(68) }
    let hole_first = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: true } }
    let (_ce, e_hole_first) = chart.choropleth(regions[..1usize], hole_first[..], vertices[..4usize], metrics[..], w_equi, bounds, &work)
    if e_hole_first != chart.Invalid { os.exit(69) }
    let tiny_ring = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 2usize, hole: false } }
    let (_cf, e_tiny_ring) = chart.choropleth(regions[..1usize], tiny_ring[..], vertices[..2usize], metrics[..], w_equi, bounds, &work)
    if e_tiny_ring != chart.Invalid { os.exit(70) }
    let flat_vertices = [4]chart.MapVertex{ chart.MapVertex { lon: 0.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 10.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 15.0f64, lat: 0.0f64 } }
    let flat_ring = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: false } }
    let (_cg, e_flat_ring) = chart.choropleth(regions[..1usize], flat_ring[..], flat_vertices[..], metrics[..], w_equi, bounds, &work)
    if e_flat_ring != chart.Invalid { os.exit(71) }
    let outside = [4]chart.MapVertex{ chart.MapVertex { lon: 0.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 90.0f64 }, chart.MapVertex { lon: 0.0f64, lat: 5.0f64 } }
    let (_ch, e_outside_window) = chart.choropleth(regions[..1usize], flat_ring[..], outside[..], metrics[..], w_equi, bounds, &work)
    if e_outside_window != chart.Invalid { os.exit(72) }
    let (_ci, e_few_rings) = chart.choropleth(regions[..], rings[..4usize], vertices[..], metrics[..], w_equi, bounds, &work)
    if e_few_rings != chart.Invalid { os.exit(73) }
    let (_cj, e_no_regions) = chart.choropleth(regions[..0usize], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)
    if e_no_regions != chart.Invalid { os.exit(74) }
    let (_ck, e_bad_bounds) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, geometry.rect(0.0, 0.0, -1.0, 10.0), &work)
    if e_bad_bounds != chart.Invalid { os.exit(75) }
    var short_points = work
    short_points.points = c_points[..27usize]
    let (_cs_points, e_short_points) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &short_points)
    if e_short_points != chart.TooLarge { os.exit(76) }
    var short_rings = work
    short_rings.rings = c_rings[..6usize]
    let (_cs_rings, e_short_rings) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &short_rings)
    if e_short_rings != chart.TooLarge { os.exit(77) }
    var short_regions = work
    short_regions.regions = c_regions[..4usize]
    let (_cs_regions, e_short_regions) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &short_regions)
    if e_short_regions != chart.TooLarge { os.exit(78) }
    let (written, write_error) = os.write(os.stdout(), "gfx chart map reference ok\n")
    os.exit(0)
    ret ok
}
