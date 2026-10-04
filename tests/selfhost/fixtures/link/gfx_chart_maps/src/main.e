use e.algo.geo
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.0001f64 && b - a < 0.0001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let window = geo.MapWindow { projection: .Equirectangular, center_lon: 180.0f64, half_lon_span: 10.0f64, south_lat: 0.0f64, north_lat: 20.0f64 }
    let (left, middle, project_error) = geo.map_project(178.0f64, 10.0f64, window)
    let (right, _, wrapped_error) = geo.map_project(-178.0f64, 10.0f64, window)
    if project_error != ok || wrapped_error != ok || !near(left, 0.4f64) || !near(right, 0.6f64) || !near(middle, 0.5f64) { ret chart.Invalid }
    let mercator = geo.MapWindow { projection: .Mercator, center_lon: 0.0f64, half_lon_span: 180.0f64, south_lat: -80.0f64, north_lat: 80.0f64 }
    let (center_x, center_y, mercator_error) = geo.map_project(0.0f64, 0.0f64, mercator)
    if mercator_error != ok || !near(center_x, 0.5f64) || !near(center_y, 0.5f64) { ret chart.Invalid }
    let regions = [3]chart.MapRegion{ chart.MapRegion { key: "A" }, chart.MapRegion { key: "B" }, chart.MapRegion { key: "C" } }
    let rings = [4]chart.MapRing{
        chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: false },
        chart.MapRing { region: 0usize, first: 4usize, count: 4usize, hole: true },
        chart.MapRing { region: 1usize, first: 8usize, count: 4usize, hole: false },
        chart.MapRing { region: 2usize, first: 12usize, count: 4usize, hole: false },
    }
    let vertices = [16]chart.MapVertex{
        chart.MapVertex { lon: 178.0f64, lat: 10.0f64 }, chart.MapVertex { lon: -178.0f64, lat: 10.0f64 }, chart.MapVertex { lon: -178.0f64, lat: 14.0f64 }, chart.MapVertex { lon: 178.0f64, lat: 14.0f64 },
        chart.MapVertex { lon: 179.0f64, lat: 11.0f64 }, chart.MapVertex { lon: -179.0f64, lat: 11.0f64 }, chart.MapVertex { lon: -179.0f64, lat: 13.0f64 }, chart.MapVertex { lon: 179.0f64, lat: 13.0f64 },
        chart.MapVertex { lon: 175.0f64, lat: 5.0f64 }, chart.MapVertex { lon: 177.0f64, lat: 5.0f64 }, chart.MapVertex { lon: 177.0f64, lat: 7.0f64 }, chart.MapVertex { lon: 175.0f64, lat: 7.0f64 },
        chart.MapVertex { lon: -177.0f64, lat: 4.0f64 }, chart.MapVertex { lon: -175.0f64, lat: 4.0f64 }, chart.MapVertex { lon: -175.0f64, lat: 6.0f64 }, chart.MapVertex { lon: -177.0f64, lat: 6.0f64 },
    }
    let metrics = [2]chart.MapMetric{ chart.MapMetric { key: "B", value: 10.0f64 }, chart.MapMetric { key: "A", value: 40.0f64 } }
    var points: [16]chart.Coord = zero
    var projected_rings: [4]chart.MapProjectedRing = zero
    var region_layouts: [3]chart.MapRegionLayout = zero
    var work = chart.ChoroplethStorage { points: points[..], rings: projected_rings[..], regions: region_layouts[..] }
    let bounds = geometry.rect(20.0, 30.0, 200.0, 160.0)
    let (map, map_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], window, bounds, &work)
    if map_error != ok || map.regions.len != 3usize || !near(map.minimum, 10.0f64) || !near(map.maximum, 40.0f64) || !map.regions[0usize].has_value || !near(f64(map.regions[0usize].fraction), 1.0f64) || !near(f64(map.regions[1usize].fraction), 0.0f64) || map.regions[2usize].has_value || map.regions[0usize].rings[0usize].reverse == map.regions[0usize].rings[1usize].reverse || !near(f64(points[0usize].x), 100.0f64) || !near(f64(points[1usize].x), 140.0f64) { ret chart.Invalid }
    let sites = [4]chart.MapSite{
        chart.MapSite { key: "A", lon: 179.0f64, lat: 10.0f64, value: 100.0f64, present: true },
        chart.MapSite { key: "B", lon: -179.0f64, lat: 10.0f64, value: 25.0f64, present: true },
        chart.MapSite { key: "C", lon: 176.0f64, lat: 8.0f64, value: 0.0f64, present: true },
        chart.MapSite { key: "D", lon: -176.0f64, lat: 8.0f64, value: 0.0f64, present: false },
    }
    var circles: [4]geometry.Rect = zero
    let (symbols, symbols_error) = chart.proportional_symbol_map(sites[..], window, bounds, 10.0f32, circles[..])
    if symbols_error != ok || symbols.present_count != 3usize || !near(symbols.maximum, 100.0f64) || !near(f64(circles[0usize].width), 20.0f64) || !near(f64(circles[1usize].width), 10.0f64) || circles[2usize].width != 0.0f32 || circles[3usize].width != 0.0f32 { ret chart.Invalid }
    let ink = paint.rgba(0.2, 0.5, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_map_region(a, &builder, &map.regions[0usize], paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &symbols.marks, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 240.0f32, 220.0f32, "Map", "Holes and symbols")
    try chart_svg.append_map_region(&writer, &map.regions[0usize], ink)
    try chart_svg.append(&writer, &symbols.marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "fill-rule=\"nonzero\"") || !str.contains(svg, "<circle") { ret chart.Invalid }
    var short = work
    short.points = points[..15usize]
    let (_, short_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], window, bounds, &short)
    let seam_window = geo.MapWindow { projection: .Equirectangular, center_lon: 0.0f64, half_lon_span: 180.0f64, south_lat: 0.0f64, north_lat: 20.0f64 }
    let (_, seam_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], seam_window, bounds, &work)
    let duplicate_metrics = [2]chart.MapMetric{ chart.MapMetric { key: "A", value: 10.0f64 }, chart.MapMetric { key: "A", value: 20.0f64 } }
    let (_, duplicate_error) = chart.choropleth(regions[..], rings[..], vertices[..], duplicate_metrics[..], window, bounds, &work)
    let first_hole = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: true } }
    let (_, hole_error) = chart.choropleth(regions[..1usize], first_hole[..], vertices[..4usize], metrics[..1usize], window, bounds, &work)
    let bad_mercator = geo.MapWindow { projection: .Mercator, center_lon: 0.0f64, half_lon_span: 180.0f64, south_lat: -90.0f64, north_lat: 80.0f64 }
    let (_, _, mercator_limit) = geo.map_project(0.0f64, 0.0f64, bad_mercator)
    let (_, narrow_error) = chart.proportional_symbol_map(sites[..], window, bounds, 10.0f32, circles[..3usize])
    if short_error != chart.TooLarge || seam_error != chart.Invalid || duplicate_error != chart.Invalid || hole_error != chart.Invalid || mercator_limit != geo.Invalid || narrow_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart maps ok\n")
    ret ok
}
