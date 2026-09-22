// `e.algo.geo`: S2 cell ids for 24 (lat, lng, level) triples (six face
// centres, the poles, the antimeridian, level 30) fold to the reference
// library's hash, level/face/parent/children/contains/range agree, tokens
// and edge neighbours match, centres roundtrip within 1e-9 degrees, and the
// London-Paris haversine is within 1 m. Each check exits with its own code.

use e.algo.geo
use e.io
use e.math
use e.mem
use e.os

fn close(a: f64, b: f64, tol: f64) -> bool { ret math.abs[f64](a - b) <= tol }

fn main(a: *mem.Arena, args: []str) -> err {
    let lats = [24]f64{ 0.0, 0.0, 90.0, 0.0, 0.0, -90.0, 90.0, -90.0, 0.0, 45.0, -30.0, 10.0, 51.5074, 48.8566, 51.5074, 48.8566, 35.6895, -33.8688, 40.7128, -22.9068, 64.1466, -77.8463, 1.3521, 55.7558 }
    let lngs = [24]f64{ 0.0, 90.0, 0.0, 180.0, -90.0, 0.0, 45.0, -120.0, -180.0, -179.5, 179.999, -179.999, -0.1278, 2.3522, -0.1278, 2.3522, 139.6917, 151.2093, -74.006, -43.1729, -21.9426, 166.6682, 103.8198, 37.6173 }
    let levels = [24]u32{ 30u32, 30u32, 30u32, 30u32, 30u32, 30u32, 12u32, 20u32, 30u32, 16u32, 30u32, 8u32, 30u32, 30u32, 10u32, 0u32, 25u32, 5u32, 1u32, 30u32, 30u32, 18u32, 29u32, 3u32 }
    var ids: [24]u64 = zero

    // 1: the 24 ids fold to the reference hash; three compared directly.
    var h = 0u64
    var k = 0usize
    while k < 24usize {
        ids[k] = geo.s2_cell(lats[k], lngs[k], levels[k])
        h = h *% 6364136223846793005u64 +% ids[k]
        k += 1usize
    }
    if h != 7376273696988961072u64 { os.exit(1i32) }
    if ids[0usize] != 1152921504606846977u64 || ids[12usize] != 5221366101706051497u64 || ids[15usize] != 5764607523034234880u64 { os.exit(1i32) }
    if geo.s2_cell_leaf(51.5074f64, -0.1278f64) != ids[12usize] { os.exit(1i32) }

    // 2: level, face, parent, children, contains, range of London at level 10.
    let london = ids[14usize]
    if london != 5221366315540807680u64 || geo.s2_level(london) != 10u32 || geo.s2_face(london) != 2u32 { os.exit(2i32) }
    if geo.s2_parent(london, 4u32) != 5219671968122404864u64 { os.exit(2i32) }
    if geo.s2_parent(ids[12usize], 10u32) != london { os.exit(2i32) }
    var kids: [4]u64 = zero
    geo.s2_children(london, kids[..])
    if kids[0usize] != 5221365490907086848u64 || kids[1usize] != 5221366040662900736u64 || kids[2usize] != 5221366590418714624u64 || kids[3usize] != 5221367140174528512u64 { os.exit(2i32) }
    let (lo, hi) = geo.s2_range(london)
    if lo != 5221365216029179905u64 || hi != 5221367415052435455u64 { os.exit(2i32) }
    k = 0usize
    while k < 4usize {
        if geo.s2_level(kids[k]) != 11u32 || geo.s2_face(kids[k]) != 2u32 || geo.s2_parent(kids[k], 10u32) != london { os.exit(2i32) }
        if !geo.s2_contains(london, kids[k]) || kids[k] < lo || kids[k] > hi { os.exit(2i32) }
        k += 1usize
    }
    if !geo.s2_contains(london, ids[12usize]) || geo.s2_contains(london, ids[13usize]) || !geo.s2_contains(ids[15usize], ids[13usize]) { os.exit(2i32) }
    if geo.s2_level(ids[15usize]) != 0u32 || geo.s2_level(ids[12usize]) != 30u32 { os.exit(2i32) }

    // 3: tokens for three ids.
    var tok: [16]u8 = zero
    var n = geo.s2_token(ids[12usize], tok[..])
    if n != 16usize || !same(tok[..n], "487604ce36748fa9") { os.exit(3i32) }
    n = geo.s2_token(london, tok[..])
    if n != 6usize || !same(tok[..n], "487605") { os.exit(3i32) }
    n = geo.s2_token(ids[15usize], tok[..])
    if n != 1usize || !same(tok[..n], "5") { os.exit(3i32) }
    n = geo.s2_token(0u64, tok[..])
    if n != 1usize || !same(tok[..n], "X") { os.exit(3i32) }

    // 4: centres within 1e-9 degrees of the reference.
    let (lat0, lng0) = geo.s2_center(ids[12usize])
    if !close(lat0, 51.507400008985336f64, 1.0e-9f64) || !close(lng0, -0.12780003943886298f64, 1.0e-9f64) { os.exit(4i32) }
    let (lat1, lng1) = geo.s2_center(london)
    if !close(lat1, 51.472885290247405f64, 1.0e-9f64) || !close(lng1, -0.14075434208431364f64, 1.0e-9f64) { os.exit(4i32) }
    let (lat2, lng2) = geo.s2_center(ids[6usize])
    if !close(lat2, 89.98681016305451f64, 1.0e-9f64) || !close(lng2, -135.0f64, 1.0e-9f64) { os.exit(4i32) }
    let (lat3, lng3) = geo.s2_center(ids[9usize])
    if !close(lat3, 44.99949026515869f64, 1.0e-9f64) || !close(lng3, -179.49960213963635f64, 1.0e-9f64) { os.exit(4i32) }
    let (lat4, lng4) = geo.s2_center(ids[20usize])
    if !close(lat4, 64.14659997760087f64, 1.0e-9f64) || !close(lng4, -21.942600012615127f64, 1.0e-9f64) { os.exit(4i32) }

    // 5: edge neighbours, inside a face and across face edges.
    var nb: [4]u64 = zero
    geo.s2_neighbors(london, nb[..])
    if nb[0usize] != 5221364116517552128u64 || nb[1usize] != 5221390504796618752u64 || nb[2usize] != 5221377310657085440u64 || nb[3usize] != 5221368514564063232u64 { os.exit(5i32) }
    let edge = 18014398509481984u64
    geo.s2_neighbors(edge, nb[..])
    if nb[0usize] != 13817043656772681728u64 || nb[1usize] != 126100789566373888u64 || nb[2usize] != 54043195528445952u64 || nb[3usize] != 10754595910160744448u64 { os.exit(5i32) }
    k = 0usize
    while k < 4usize {
        if geo.s2_level(nb[k]) != 3u32 { os.exit(5i32) }
        k += 1usize
    }

    // 6: haversine and bearing London-Paris.
    let d = geo.haversine_m(51.5074f64, -0.1278f64, 48.8566f64, 2.3522f64)
    if !close(d, 343556.5348808832f64, 1.0f64) { os.exit(6i32) }
    if !close(geo.bearing_deg(51.5074f64, -0.1278f64, 48.8566f64, 2.3522f64), 148.11561687105336f64, 1.0e-9f64) { os.exit(6i32) }

    try io.print("algo geo ok\n")
    ret ok
}

fn same(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}
