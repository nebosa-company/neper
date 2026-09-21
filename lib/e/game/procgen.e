// Procedural generation: wave function collapse over tile adjacencies, and Perlin,
// simplex and Worley noise.
//
// Noise is `f64` and seeded through a `Perm`: `perm(0)` is Ken Perlin's reference
// permutation and any other seed shuffles it with `e.algo.rand`'s PCG (stream 0), so a
// seed answers the same field on every machine. `perlin` is the 2002 improved noise
// evaluated at `z = 0` (`perlin3` is the full thing), `simplex` is Gustavson's 2-d
// simplex with the twelve `grad3` gradients scaled by 70, and `worley` puts one feature
// point per unit cell -- drawn from a PCG seeded by the cell and `seed` -- and answers
// the nearest two distances over the 3x3 neighbourhood.
//
// `wave_function_collapse` takes up to 64 tiles with an allowed-neighbour mask per tile
// and direction (`allow[t * 4 + d]`, `d` 0 east, 1 south, 2 west, 3 north; make the
// masks symmetric, only the forward direction is propagated). The order is fixed so a
// run replays: the cell to collapse is the entropy minimum (fewest tiles left, ties
// broken by one `pcg64_bounded` draw over the tied cells in index order), the tile is a
// `pcg64_bounded` draw over its remaining tiles in bit order, and propagation is a LIFO
// stack visiting directions 0..3. An emptied domain answers `Invalid`.

use e.algo.rand
use e.bytes
use e.math

type Perm = struct { p: [512]u8 }

error Invalid
error TooSmall

fn perm(seed: u64) -> Perm {
    var table: [256]u8 = [256]u8{
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
        247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
        57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
        74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
        60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
        65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
        200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
        52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
        207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
        119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
        129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
        218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
        81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
        184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
        222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180 }
    if seed != 0u64 {
        var r = rand.pcg64(seed, 0u64)
        rand.shuffle[u8](&r, table[..])
    }
    var out: Perm = zero
    var i = 0usize
    while i < 256usize {
        out.p[i] = table[i]
        out.p[i + 256usize] = table[i]
        i += 1usize
    }
    ret out
}

fn look(p: *const Perm, i: usize) -> usize { ret usize(p.p[i]) }

fn fade(t: f64) -> f64 { ret t * t * t * (t * (t * 6.0f64 - 15.0f64) + 10.0f64) }

fn lerp(t: f64, a: f64, b: f64) -> f64 { ret a + t * (b - a) }

fn grad(hash: usize, x: f64, y: f64, z: f64) -> f64 {
    let h = hash & 15usize
    var u = y
    if h < 8usize { u = x }
    var v = z
    if h < 4usize {
        v = y
    } else {
        if h == 12usize || h == 14usize { v = x }
    }
    if (h & 1usize) != 0usize { u = 0.0f64 - u }
    if (h & 2usize) != 0usize { v = 0.0f64 - v }
    ret u + v
}

// The lattice cell of `v`, masked to the table, and the offset inside it.
fn lattice(v: f64) -> (usize, f64) {
    let fl = math.floor[f64](v)
    ret (usize(i64(fl) & 255i64), v - fl)
}

// Perlin's improved noise (2002), in [-1, 1].
fn perlin3(p: *const Perm, xin: f64, yin: f64, zin: f64) -> f64 {
    let (xi, x) = lattice(xin)
    let (yi, y) = lattice(yin)
    let (zi, z) = lattice(zin)
    let u = fade(x)
    let v = fade(y)
    let w = fade(z)
    let a = look(p, xi) + yi
    let aa = look(p, a) + zi
    let ab = look(p, a + 1usize) + zi
    let b = look(p, xi + 1usize) + yi
    let ba = look(p, b) + zi
    let bb = look(p, b + 1usize) + zi
    let x1 = x - 1.0f64
    let y1 = y - 1.0f64
    let z1 = z - 1.0f64
    let front = lerp(v, lerp(u, grad(look(p, aa), x, y, z), grad(look(p, ba), x1, y, z)), lerp(u, grad(look(p, ab), x, y1, z), grad(look(p, bb), x1, y1, z)))
    let back = lerp(v, lerp(u, grad(look(p, aa + 1usize), x, y, z1), grad(look(p, ba + 1usize), x1, y, z1)), lerp(u, grad(look(p, ab + 1usize), x, y1, z1), grad(look(p, bb + 1usize), x1, y1, z1)))
    ret lerp(w, front, back)
}

fn perlin(p: *const Perm, x: f64, y: f64) -> f64 { ret perlin3(p, x, y, 0.0f64) }

// The twelve `grad3` gradients projected to the plane: four diagonals, then the axes.
fn grad2(gi: usize, x: f64, y: f64) -> f64 {
    var gx = 1.0f64
    var gy = 1.0f64
    if (gi & 1usize) != 0usize { gx = -1.0f64 }
    if gi < 4usize {
        if (gi & 2usize) != 0usize { gy = -1.0f64 }
    } else {
        if gi < 8usize {
            gy = 0.0f64
        } else {
            gx = 0.0f64
            if (gi & 1usize) != 0usize { gy = -1.0f64 }
        }
    }
    ret gx * x + gy * y
}

fn corner(t0: f64, gi: usize, x: f64, y: f64) -> f64 {
    if t0 < 0.0f64 { ret 0.0f64 }
    let t = t0 * t0
    ret t * t * grad2(gi, x, y)
}

// Gustavson's 2-d simplex noise, roughly in [-1, 1].
fn simplex(p: *const Perm, xin: f64, yin: f64) -> f64 {
    let root3 = math.sqrt[f64](3.0f64)
    let f2 = 0.5f64 * (root3 - 1.0f64)
    let g2 = (3.0f64 - root3) / 6.0f64
    let s = (xin + yin) * f2
    let i = math.floor[f64](xin + s)
    let j = math.floor[f64](yin + s)
    let t = (i + j) * g2
    let x0 = xin - (i - t)
    let y0 = yin - (j - t)
    var i1 = 0usize
    var j1 = 1usize
    if x0 > y0 {
        i1 = 1usize
        j1 = 0usize
    }
    let x1 = x0 - f64(i1) + g2
    let y1 = y0 - f64(j1) + g2
    let x2 = x0 - 1.0f64 + 2.0f64 * g2
    let y2 = y0 - 1.0f64 + 2.0f64 * g2
    let ii = usize(i64(i) & 255i64)
    let jj = usize(i64(j) & 255i64)
    let gi0 = look(p, ii + look(p, jj)) % 12usize
    let gi1 = look(p, ii + i1 + look(p, jj + j1)) % 12usize
    let gi2 = look(p, ii + 1usize + look(p, jj + 1usize)) % 12usize
    let n0 = corner(0.5f64 - x0 * x0 - y0 * y0, gi0, x0, y0)
    let n1 = corner(0.5f64 - x1 * x1 - y1 * y1, gi1, x1, y1)
    let n2 = corner(0.5f64 - x2 * x2 - y2 * y2, gi2, x2, y2)
    ret 70.0f64 * (n0 + n1 + n2)
}

// Two's complement, since `u64(v)` refuses a negative.
fn wrap(v: i64) -> u64 {
    if v >= 0i64 { ret u64(v) }
    ret 18446744073709551615u64 - u64(0i64 - v - 1i64)
}

fn cell_seed(ix: i64, iy: i64, seed: u64) -> u64 {
    ret (wrap(ix) *% 11400714819323198485u64) ^ (wrap(iy) *% 14029467366897019727u64) ^ seed
}

// Cellular noise: the distances to the nearest and second-nearest feature points.
fn worley(x: f64, y: f64, seed: u64) -> (f64, f64) {
    let cx = i64(math.floor[f64](x))
    let cy = i64(math.floor[f64](y))
    var f1 = 1.0e300f64
    var f2 = 1.0e300f64
    var dy = -1i64
    while dy <= 1i64 {
        var dx = -1i64
        while dx <= 1i64 {
            let ix = cx + dx
            let iy = cy + dy
            var r = rand.pcg64(cell_seed(ix, iy, seed), 0u64)
            let px = f64(ix) + rand.pcg64_f64(&r)
            let py = f64(iy) + rand.pcg64_f64(&r)
            let d = math.sqrt[f64]((px - x) * (px - x) + (py - y) * (py - y))
            if d < f1 {
                f2 = f1
                f1 = d
            } else {
                if d < f2 { f2 = d }
            }
            dx += 1i64
        }
        dy += 1i64
    }
    ret (f1, f2)
}

// --- wave function collapse ------------------------------------------------------------

fn neighbour(w: usize, h: usize, cell: usize, d: usize) -> (usize, bool) {
    let x = cell % w
    let y = cell / w
    if d == 0usize {
        if x + 1usize >= w { ret (0usize, false) }
        ret (cell + 1usize, true)
    }
    if d == 1usize {
        if y + 1usize >= h { ret (0usize, false) }
        ret (cell + w, true)
    }
    if d == 2usize {
        if x == 0usize { ret (0usize, false) }
        ret (cell - 1usize, true)
    }
    if y == 0usize { ret (0usize, false) }
    ret (cell - w, true)
}

// The `k`-th set bit of `v`, lowest first.
fn nth_bit(v: u64, k: u64) -> u32 {
    var rest = v
    var skip = k
    while skip > 0u64 {
        rest = rest & (rest - 1u64)
        skip -= 1u64
    }
    ret bytes.trailing_zeros[u64](rest)
}

// `domains` and `out` are one per cell; `stack` is the propagation stack, and a cell may
// sit on it once per shrink, so `4 * w * h` entries are always enough.
fn wave_function_collapse(allow: []const u64, tiles: usize, w: usize, h: usize, r: *rand.Pcg64, domains: []u64, stack: []u32, out: []u8) -> err {
    let cells = w * h
    if tiles == 0usize || tiles > 64usize || allow.len < tiles * 4usize { ret Invalid }
    if domains.len < cells || out.len < cells { ret TooSmall }
    var full = 18446744073709551615u64
    if tiles < 64usize { full = (1u64 << u32(tiles)) - 1u64 }
    var i = 0usize
    while i < cells {
        domains[i] = full
        i += 1usize
    }
    while true {
        // ponytail: a full scan per collapse, O(cells) each; a bucket queue by entropy if grids grow.
        var best = 65u32
        var ties = 0u64
        i = 0usize
        while i < cells {
            let n = bytes.count_ones[u64](domains[i])
            if n > 1u32 {
                if n < best {
                    best = n
                    ties = 1u64
                } else {
                    if n == best { ties += 1u64 }
                }
            }
            i += 1usize
        }
        if ties == 0u64 { break }
        let pick = rand.pcg64_bounded(r, ties)
        var seen = 0u64
        var cell = 0usize
        i = 0usize
        while i < cells {
            if bytes.count_ones[u64](domains[i]) == best {
                if seen == pick {
                    cell = i
                    break
                }
                seen += 1u64
            }
            i += 1usize
        }
        let choice = rand.pcg64_bounded(r, u64(best))
        domains[cell] = 1u64 << nth_bit(domains[cell], choice)
        if stack.len == 0usize { ret TooSmall }
        stack[0usize] = u32(cell)
        var depth = 1usize
        while depth > 0usize {
            depth -= 1usize
            let c = usize(stack[depth])
            var d = 0usize
            while d < 4usize {
                let (n, inside) = neighbour(w, h, c, d)
                d += 1usize
                if !inside { continue }
                var allowed = 0u64
                var t = 0usize
                while t < tiles {
                    if ((domains[c] >> u32(t)) & 1u64) != 0u64 { allowed = allowed | allow[t * 4usize + d - 1usize] }
                    t += 1usize
                }
                let shrunk = domains[n] & allowed
                if shrunk == 0u64 { ret Invalid }
                if shrunk != domains[n] {
                    domains[n] = shrunk
                    if depth == stack.len { ret TooSmall }
                    stack[depth] = u32(n)
                    depth += 1usize
                }
            }
        }
    }
    i = 0usize
    while i < cells {
        out[i] = u8(bytes.trailing_zeros[u64](domains[i]))
        i += 1usize
    }
    ret ok
}
