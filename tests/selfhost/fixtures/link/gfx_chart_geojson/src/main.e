// GeoJSON polygons into choropleth arrays, and equal-interval colour classes with
// their legend (D2115): a holed Polygon, a two-part MultiPolygon, a null geometry
// left out and positions with altitude, keyed by a property and by `id`; the
// refusals; and the classes' arithmetic.
use e.algo.geo
use e.gfx.chart
use e.gfx.chart.geojson
use e.gfx.geometry
use e.io
use e.mem
use e.os
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.000001f64 && b - a < 0.000001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let text = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"id\":7,\"properties\":{\"name\":\"A\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[4,0],[4,4],[0,4],[0,0]],[[1,1],[1,2],[2,2],[2,1],[1,1]]]}},{\"type\":\"Feature\",\"id\":\"b\",\"properties\":{\"name\":\"B\"},\"geometry\":{\"type\":\"MultiPolygon\",\"coordinates\":[[[[5,0],[6,0],[6,1],[5,1],[5,0]]],[[[7,0],[8,0],[8,1.5],[7,1],[7,0]]]]}},{\"type\":\"Feature\",\"id\":\"n\",\"properties\":{\"name\":\"N\"},\"geometry\":null},{\"type\":\"Feature\",\"id\":\"c\",\"properties\":{\"name\":\"C\",\"rank\":2},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,5,100],[2,5,100],[2,7,100],[0,7,100],[0,5,100]]]}}]}"
    let (m, read_error) = geojson.read(a, text, "name")
    if read_error != ok { os.exit(1i32) }
    if m.regions.len != 3usize || m.rings.len != 5usize || m.vertices.len != 20usize { os.exit(2i32) }
    if !str.eq(m.regions[0usize].key, "A") || !str.eq(m.regions[1usize].key, "B") || !str.eq(m.regions[2usize].key, "C") { os.exit(3i32) }
    // The hole follows its exterior; a MultiPolygon's parts are both exteriors.
    let r = m.rings
    if r[0usize].region != 0usize || r[0usize].first != 0usize || r[0usize].count != 4usize || r[0usize].hole { os.exit(4i32) }
    if r[1usize].region != 0usize || r[1usize].first != 4usize || !r[1usize].hole { os.exit(5i32) }
    if r[2usize].region != 1usize || r[2usize].first != 8usize || r[2usize].hole || r[3usize].region != 1usize || r[3usize].first != 12usize || r[3usize].hole { os.exit(6i32) }
    if r[4usize].region != 2usize || r[4usize].first != 16usize || r[4usize].count != 4usize { os.exit(7i32) }
    // The closing position is dropped and the altitude ignored.
    if !near(m.vertices[3usize].lon, 0.0f64) || !near(m.vertices[3usize].lat, 4.0f64) || !near(m.vertices[14usize].lat, 1.5f64) || !near(m.vertices[17usize].lon, 2.0f64) || !near(m.vertices[19usize].lat, 7.0f64) { os.exit(8i32) }
    // Keyed by `id`: a number by its text.
    let (by_id, id_error) = geojson.read(a, text, "")
    if id_error != ok || !str.eq(by_id.regions[0usize].key, "7") || !str.eq(by_id.regions[1usize].key, "b") || !str.eq(by_id.regions[2usize].key, "c") { os.exit(9i32) }
    // The arrays drive a choropleth as they stand.
    let metrics = [3]chart.MapMetric{
        chart.MapMetric { key: "A", value: 10.0f64 }, chart.MapMetric { key: "B", value: 35.0f64 }, chart.MapMetric { key: "C", value: 60.0f64 },
    }
    let window = geo.MapWindow { projection: .Equirectangular, center_lon: 4.0f64, half_lon_span: 5.0f64, south_lat: -1.0f64, north_lat: 8.0f64 }
    var points: [20]chart.Coord = zero
    var projected: [5]chart.MapProjectedRing = zero
    var layouts: [3]chart.MapRegionLayout = zero
    var work = chart.ChoroplethStorage { points: points[..], rings: projected[..], regions: layouts[..] }
    let (map, map_error) = chart.choropleth(m.regions, m.rings, m.vertices, metrics[..], window, geometry.rect(0.0, 0.0, 200.0, 180.0), &work)
    if map_error != ok || map.regions.len != 3usize || map.regions[0usize].rings.len != 2usize || map.regions[1usize].rings.len != 2usize || !near(map.minimum, 10.0f64) || !near(map.maximum, 60.0f64) { os.exit(10i32) }
    // Refusals.
    let point = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"P\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]}}]}"
    let (_, point_error) = geojson.read(a, point, "name")
    if point_error != geojson.Unsupported { os.exit(11i32) }
    let open = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"O\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[1,0],[1,1],[0,1],[0,0.5]]]}}]}"
    let (_, open_error) = geojson.read(a, open, "name")
    if open_error != geojson.Invalid { os.exit(12i32) }
    let short = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"name\":\"S\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[1,0],[0,0]]]}}]}"
    let (_, short_error) = geojson.read(a, short, "name")
    if short_error != geojson.Invalid { os.exit(13i32) }
    let (_, unkeyed_error) = geojson.read(a, text, "missing")
    if unkeyed_error != geojson.Invalid { os.exit(14i32) }
    let (_, rank_error) = geojson.read(a, text, "rank")
    if rank_error != geojson.Invalid { os.exit(15i32) }
    let (_, kind_error) = geojson.read(a, "{\"type\":\"Feature\",\"features\":[]}", "name")
    if kind_error != geojson.Invalid { os.exit(16i32) }
    let (_, syntax_error) = geojson.read(a, "{\"type\":", "name")
    if syntax_error == ok { os.exit(17i32) }
    let (empty, empty_error) = geojson.read(a, "{\"type\":\"FeatureCollection\",\"features\":[]}", "name")
    if empty_error != ok || empty.regions.len != 0usize { os.exit(18i32) }
    // Equal-interval classes: the maximum falls in the top class.
    if chart.class_of(0.0, 5usize) != 0usize || chart.class_of(0.19, 5usize) != 0usize || chart.class_of(0.2, 5usize) != 1usize || chart.class_of(0.99, 5usize) != 4usize || chart.class_of(1.0, 5usize) != 4usize || chart.class_of(0.5, 0usize) != 0usize { os.exit(19i32) }
    var swatches: [5]geometry.Rect = zero
    var breaks: [6]chart.Tick = zero
    let (legend, legend_error) = chart.class_legend(10.0f64, 60.0f64, 5usize, geometry.rect(0.0, 0.0, 100.0, 10.0), swatches[..], breaks[..])
    if legend_error != ok || legend.swatches.len != 5usize || legend.breaks.len != 6usize { os.exit(20i32) }
    if !near(f64(legend.swatches[1usize].x), 20.0f64) || !near(f64(legend.swatches[4usize].width), 20.0f64) || !near(f64(legend.breaks[0usize].value), 10.0f64) || !near(f64(legend.breaks[2usize].value), 30.0f64) || !near(f64(legend.breaks[2usize].fraction), 0.4f64) || !near(f64(legend.breaks[5usize].value), 60.0f64) { os.exit(21i32) }
    let (_, none_error) = chart.class_legend(10.0f64, 60.0f64, 0usize, geometry.rect(0.0, 0.0, 100.0, 10.0), swatches[..], breaks[..])
    let (_, reversed_error) = chart.class_legend(60.0f64, 10.0f64, 5usize, geometry.rect(0.0, 0.0, 100.0, 10.0), swatches[..], breaks[..])
    let (_, room_error) = chart.class_legend(10.0f64, 60.0f64, 5usize, geometry.rect(0.0, 0.0, 100.0, 10.0), swatches[..], breaks[..5usize])
    if none_error != chart.Invalid || reversed_error != chart.Invalid || room_error != chart.TooLarge { os.exit(22i32) }
    try io.print("gfx chart geojson ok\n")
    ret ok
}
