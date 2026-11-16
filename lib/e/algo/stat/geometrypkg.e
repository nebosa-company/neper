// R geometry convhulln with the FA option for points in the plane and in space: the number of hull facets (edges or triangles), the boundary measure (perimeter or surface area) and the enclosed measure (area or volume). The plane uses Andrew's monotone chain; space tests every point triple for a supporting plane (points in general position, up to a few dozen).
//
// Not here: dimensions above three, Delaunay triangulation and Voronoi diagrams, the other Qhull options, coplanar degeneracies, tsearch and inhulln.

use e.math

// out: facets, boundary measure, enclosed measure; p is n by 2 row-major
fn hull2(p: []const f64, n: usize, out: []f64) {
    var idx: [64]usize = zero
    var i = 0usize
    while i < n {
        idx[i] = i
        i += 1usize
    }
    // sort indices by x then y
    i = 1usize
    while i < n {
        let v = idx[i]
        var j = i
        while j > 0usize && (p[idx[j - 1usize] * 2usize] > p[v * 2usize] || (p[idx[j - 1usize] * 2usize] == p[v * 2usize] && p[idx[j - 1usize] * 2usize + 1usize] > p[v * 2usize + 1usize])) {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = v
        i += 1usize
    }
    var hull: [128]usize = zero
    var k = 0usize
    i = 0usize
    while i < n {
        while k >= 2usize && cross2(p, hull[k - 2usize], hull[k - 1usize], idx[i]) <= 0.0f64 { k -= 1usize }
        hull[k] = idx[i]
        k += 1usize
        i += 1usize
    }
    let lower = k + 1usize
    i = n - 1usize
    while i > 0usize {
        i -= 1usize
        while k >= lower && cross2(p, hull[k - 2usize], hull[k - 1usize], idx[i]) <= 0.0f64 { k -= 1usize }
        hull[k] = idx[i]
        k += 1usize
    }
    let m = k - 1usize
    var per = 0.0f64
    var ar = 0.0f64
    i = 0usize
    while i < m {
        let a = hull[i]
        let b = hull[i + 1usize]
        let dx = p[b * 2usize] - p[a * 2usize]
        let dy = p[b * 2usize + 1usize] - p[a * 2usize + 1usize]
        per += math.sqrt[f64](dx * dx + dy * dy)
        ar += p[a * 2usize] * p[b * 2usize + 1usize] - p[b * 2usize] * p[a * 2usize + 1usize]
        i += 1usize
    }
    out[0usize] = f64(m)
    out[1usize] = per
    out[2usize] = math.abs[f64](ar) / 2.0f64
}

fn cross2(p: []const f64, a: usize, b: usize, c: usize) -> f64 {
    ret (p[b * 2usize] - p[a * 2usize]) * (p[c * 2usize + 1usize] - p[a * 2usize + 1usize]) - (p[b * 2usize + 1usize] - p[a * 2usize + 1usize]) * (p[c * 2usize] - p[a * 2usize])
}

// out: facets, surface area, volume; p is n by 3 row-major
fn hull3(p: []const f64, n: usize, out: []f64) {
    var cx = 0.0f64
    var cy = 0.0f64
    var cz = 0.0f64
    var i = 0usize
    while i < n {
        cx += p[i * 3usize] / f64(n)
        cy += p[i * 3usize + 1usize] / f64(n)
        cz += p[i * 3usize + 2usize] / f64(n)
        i += 1usize
    }
    var facets = 0.0f64
    var area = 0.0f64
    var vol = 0.0f64
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            var k = j + 1usize
            while k < n {
                let ux = p[j * 3usize] - p[i * 3usize]
                let uy = p[j * 3usize + 1usize] - p[i * 3usize + 1usize]
                let uz = p[j * 3usize + 2usize] - p[i * 3usize + 2usize]
                let vx = p[k * 3usize] - p[i * 3usize]
                let vy = p[k * 3usize + 1usize] - p[i * 3usize + 1usize]
                let vz = p[k * 3usize + 2usize] - p[i * 3usize + 2usize]
                let nx = uy * vz - uz * vy
                let ny = uz * vx - ux * vz
                let nz = ux * vy - uy * vx
                var pos = 0usize
                var neg = 0usize
                var m = 0usize
                while m < n {
                    if m != i && m != j && m != k {
                        let s = nx * (p[m * 3usize] - p[i * 3usize]) + ny * (p[m * 3usize + 1usize] - p[i * 3usize + 1usize]) + nz * (p[m * 3usize + 2usize] - p[i * 3usize + 2usize])
                        if s > 1.0e-12f64 { pos += 1usize }
                        if s < 0.0f64 - 1.0e-12f64 { neg += 1usize }
                    }
                    m += 1usize
                }
                if pos == 0usize || neg == 0usize {
                    facets += 1.0f64
                    area += math.sqrt[f64](nx * nx + ny * ny + nz * nz) / 2.0f64
                    let tx = p[i * 3usize] - cx
                    let ty = p[i * 3usize + 1usize] - cy
                    let tz = p[i * 3usize + 2usize] - cz
                    vol += math.abs[f64](nx * tx + ny * ty + nz * tz) / 6.0f64
                }
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    out[0usize] = facets
    out[1usize] = area
    out[2usize] = vol
}
