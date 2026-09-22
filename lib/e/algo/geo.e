// Google S2 cell ids over WGS84 degrees: lat/lng onto the unit cube (six
// faces, the S2 face/u/v conventions, quadratic ST<->UV), a 64-bit
// Hilbert-curve id at level 0..30 with the trailing sentinel bit, and the
// plain spherical distance and bearing. Everything is pure; every id is
// bit-for-bit the reference library's.

use e.bytes
use e.math

fn pi() -> f64 { ret 3.141592653589793f64 }
fn max_level() -> u32 { ret 30u32 }
fn max_size() -> i64 { ret 1073741824i64 }
fn earth_radius_m() -> f64 { ret 6371008.8f64 }

fn radians(deg: f64) -> f64 { ret deg * (pi() / 180.0f64) }
fn degrees(rad: f64) -> f64 { ret rad * (180.0f64 / pi()) }

// Hilbert curve: the (i, j) quadrant of position `p` under orientation `o`, its
// inverse, and the orientation change a child position adds.
fn pos_to_ij(o: u32, p: u32) -> u32 {
    let t = [16]u32{ 0u32, 1u32, 3u32, 2u32, 0u32, 2u32, 3u32, 1u32, 3u32, 2u32, 0u32, 1u32, 3u32, 1u32, 0u32, 2u32 }
    ret t[usize(o * 4u32 + p)]
}
fn ij_to_pos(o: u32, ij: u32) -> u32 {
    let t = [16]u32{ 0u32, 1u32, 3u32, 2u32, 0u32, 3u32, 1u32, 2u32, 2u32, 3u32, 1u32, 0u32, 2u32, 1u32, 3u32, 0u32 }
    ret t[usize(o * 4u32 + ij)]
}
fn pos_to_orientation(p: u32) -> u32 {
    if p == 0u32 { ret 1u32 }
    if p == 3u32 { ret 3u32 }
    ret 0u32
}

fn lsb(id: u64) -> u64 { ret id & (0u64 -% id) }

// The leaf id of face-local leaf coordinates (i, j), each below 2^30.
fn from_face_ij(face: u32, i: u32, j: u32) -> u64 {
    var n = u64(face) << 60u32
    var o = face & 1u32
    var k = max_level()
    while k > 0u32 {
        k -= 1u32
        let ij = ((i >> k) & 1u32) * 2u32 + ((j >> k) & 1u32)
        let p = ij_to_pos(o, ij)
        n |= u64(p) << (2u32 * k)
        o ^= pos_to_orientation(p)
    }
    ret n * 2u64 + 1u64
}

// (face, i, j, orientation) of `id`'s leaf-coordinate corner.
fn to_face_ij(id: u64) -> (u32, u32, u32, u32) {
    let face = s2_face(id)
    var o = face & 1u32
    var i = 0u32
    var j = 0u32
    var k = max_level()
    while k > 0u32 {
        k -= 1u32
        let p = u32((id >> (2u32 * k + 1u32)) & 3u64)
        let ij = pos_to_ij(o, p)
        i |= (ij >> 1u32) << k
        j |= (ij & 1u32) << k
        o ^= pos_to_orientation(p)
    }
    if (lsb(id) & 0x1111111111111110u64) != 0u64 { o ^= 1u32 }
    ret (face, i, j, o)
}

fn st_to_uv(s: f64) -> f64 {
    if s >= 0.5f64 { ret (1.0f64 / 3.0f64) * (4.0f64 * s * s - 1.0f64) }
    ret (1.0f64 / 3.0f64) * (1.0f64 - 4.0f64 * (1.0f64 - s) * (1.0f64 - s))
}
fn uv_to_st(u: f64) -> f64 {
    if u >= 0.0f64 { ret 0.5f64 * math.sqrt[f64](1.0f64 + 3.0f64 * u) }
    ret 1.0f64 - 0.5f64 * math.sqrt[f64](1.0f64 - 3.0f64 * u)
}
fn st_to_ij(s: f64) -> u32 {
    let v = i64(math.floor[f64](f64(max_size()) * s))
    if v < 0i64 { ret 0u32 }
    if v >= max_size() { ret u32(max_size() - 1i64) }
    ret u32(v)
}

fn face_uv_to_xyz(face: u32, u: f64, v: f64) -> (f64, f64, f64) {
    if face == 0u32 { ret (1.0f64, u, v) }
    if face == 1u32 { ret (0.0f64 - u, 1.0f64, v) }
    if face == 2u32 { ret (0.0f64 - u, 0.0f64 - v, 1.0f64) }
    if face == 3u32 { ret (-1.0f64, 0.0f64 - v, 0.0f64 - u) }
    if face == 4u32 { ret (v, -1.0f64, 0.0f64 - u) }
    ret (v, u, -1.0f64)
}

fn xyz_to_face_uv(x: f64, y: f64, z: f64) -> (u32, f64, f64) {
    let ax = math.abs[f64](x)
    let ay = math.abs[f64](y)
    let az = math.abs[f64](z)
    var face = 2u32
    if ax > ay { if ax > az { face = 0u32 } } else { if ay > az { face = 1u32 } }
    if face == 0u32 {
        if x < 0.0f64 { ret (3u32, z / x, y / x) }
        ret (0u32, y / x, z / x)
    }
    if face == 1u32 {
        if y < 0.0f64 { ret (4u32, z / y, (0.0f64 - x) / y) }
        ret (1u32, (0.0f64 - x) / y, z / y)
    }
    if z < 0.0f64 { ret (5u32, (0.0f64 - y) / z, (0.0f64 - x) / z) }
    ret (2u32, (0.0f64 - x) / z, (0.0f64 - y) / z)
}

// The cell containing (lat, lng) degrees at `level` (0..30).
fn s2_cell(lat_deg: f64, lng_deg: f64, level: u32) -> u64 {
    let phi = radians(lat_deg)
    let theta = radians(lng_deg)
    let cosphi = math.cos[f64](phi)
    let (face, u, v) = xyz_to_face_uv(math.cos[f64](theta) * cosphi, math.sin[f64](theta) * cosphi, math.sin[f64](phi))
    ret s2_parent(from_face_ij(face, st_to_ij(uv_to_st(u)), st_to_ij(uv_to_st(v))), level)
}

fn s2_cell_leaf(lat_deg: f64, lng_deg: f64) -> u64 { ret s2_cell(lat_deg, lng_deg, max_level()) }

fn s2_level(id: u64) -> u32 {
    if id == 0u64 { ret 0u32 }
    ret max_level() - bytes.trailing_zeros[u64](id) / 2u32
}

fn s2_face(id: u64) -> u32 { ret u32(id >> 61u32) }

// The ancestor at `level` (which must not exceed the id's own level).
fn s2_parent(id: u64, level: u32) -> u64 {
    let new_lsb = 1u64 << (2u32 * (max_level() - level))
    ret (id & (0u64 -% new_lsb)) | new_lsb
}

// The four children in Hilbert order into `out[0..4]`; a leaf has none.
fn s2_children(id: u64, out: []u64) {
    if out.len < 4usize || (id & 1u64) == 1u64 { ret }
    let child_lsb = lsb(id) >> 2u32
    var p = 0u64
    while p < 4u64 {
        out[usize(p)] = id -% 3u64 * child_lsb +% 2u64 * p * child_lsb
        p += 1u64
    }
}

// (range_min, range_max): the leaf ids covered by `id`, inclusive.
fn s2_range(id: u64) -> (u64, u64) {
    let span = lsb(id) - 1u64
    ret (id - span, id + span)
}

fn s2_contains(ancestor: u64, id: u64) -> bool {
    let (lo, hi) = s2_range(ancestor)
    ret id >= lo && id <= hi
}

// (lat, lng) degrees of the cell centre.
fn s2_center(id: u64) -> (f64, f64) {
    let (face, i, j, _) = to_face_ij(id)
    var delta = 0u32
    if (id & 1u64) == 1u64 {
        delta = 1u32
    } else if ((u64(i) ^ (id >> 2u32)) & 1u64) != 0u64 {
        delta = 2u32
    }
    let half = 0.5f64 / f64(max_size())
    let u = st_to_uv(half * f64(2u32 * i + delta))
    let v = st_to_uv(half * f64(2u32 * j + delta))
    let (x, y, z) = face_uv_to_xyz(face, u, v)
    ret (degrees(math.atan2[f64](z, math.sqrt[f64](x * x + y * y))), degrees(math.atan2[f64](y, x)))
}

// The leaf id of (i, j), which may lie one cell beyond the face and then wraps
// onto the adjacent face (the linear projection suffices for that).
fn from_face_ij_wrap(face: u32, i: i64, j: i64) -> u64 {
    if i >= 0i64 && i < max_size() && j >= 0i64 && j < max_size() { ret from_face_ij(face, u32(i), u32(j)) }
    var ci = i
    var cj = j
    if ci < -1i64 { ci = -1i64 }
    if ci > max_size() { ci = max_size() }
    if cj < -1i64 { cj = -1i64 }
    if cj > max_size() { cj = max_size() }
    let scale = 1.0f64 / f64(max_size())
    let u = scale * f64(ci * 2i64 + 1i64 - max_size())
    let v = scale * f64(cj * 2i64 + 1i64 - max_size())
    let (x, y, z) = face_uv_to_xyz(face, u, v)
    let (f2, u2, v2) = xyz_to_face_uv(x, y, z)
    ret from_face_ij(f2, st_to_ij(0.5f64 * (u2 + 1.0f64)), st_to_ij(0.5f64 * (v2 + 1.0f64)))
}

// The four edge neighbours at the same level into `out[0..4]`, in the order
// down (j-), right (i+), up (j+), left (i-).
fn s2_neighbors(id: u64, out: []u64) {
    if out.len < 4usize { ret }
    let level = s2_level(id)
    let size = i64(1u64 << (max_level() - level))
    let (face, i, j, _) = to_face_ij(id)
    let ii = i64(i)
    let jj = i64(j)
    out[0usize] = s2_parent(from_face_ij_wrap(face, ii, jj - size), level)
    out[1usize] = s2_parent(from_face_ij_wrap(face, ii + size, jj), level)
    out[2usize] = s2_parent(from_face_ij_wrap(face, ii, jj + size), level)
    out[3usize] = s2_parent(from_face_ij_wrap(face, ii - size, jj), level)
}

// The hex token: 16 lowercase digits with trailing zeros stripped, "X" for
// zero; `out` holds at least 16 bytes. Answers the length written.
fn s2_token(id: u64, out: []u8) -> usize {
    if out.len < 16usize { ret 0usize }
    if id == 0u64 {
        out[0usize] = 88u8
        ret 1usize
    }
    let digits = "0123456789abcdef"
    var n = 16usize
    var k = 0usize
    while k < 16usize {
        out[k] = digits[usize((id >> u32(60usize - 4usize * k)) & 15u64)]
        k += 1usize
    }
    while n > 1usize && out[n - 1usize] == 48u8 { n -= 1usize }
    ret n
}

// Great-circle distance in metres over the WGS84 mean radius.
fn haversine_m(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let p1 = radians(lat1)
    let p2 = radians(lat2)
    let sdp = math.sin[f64]((p2 - p1) / 2.0f64)
    let sdl = math.sin[f64](radians(lng2 - lng1) / 2.0f64)
    let a = sdp * sdp + math.cos[f64](p1) * math.cos[f64](p2) * sdl * sdl
    ret 2.0f64 * earth_radius_m() * math.atan2[f64](math.sqrt[f64](a), math.sqrt[f64](1.0f64 - a))
}

// Initial bearing from point 1 towards point 2, degrees clockwise from north in [0, 360).
fn bearing_deg(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let p1 = radians(lat1)
    let p2 = radians(lat2)
    let dl = radians(lng2 - lng1)
    let y = math.sin[f64](dl) * math.cos[f64](p2)
    let x = math.cos[f64](p1) * math.sin[f64](p2) - math.sin[f64](p1) * math.cos[f64](p2) * math.cos[f64](dl)
    var b = degrees(math.atan2[f64](y, x)) + 360.0f64
    if b >= 360.0f64 { b -= 360.0f64 }
    ret b
}
