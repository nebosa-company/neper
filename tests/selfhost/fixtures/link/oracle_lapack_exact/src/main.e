// e.algo.linalg.lapack_syevr and lapack_gesdd against R: eigen(symmetric = TRUE) and svd() compared vector for vector,
// signs included. tests/oracle/lapack_exact.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lapack_exact`;
// the argument layout and the closed-form matrices are at the top of scripts/r_oracle/groups/lapack_exact.R.

use e.algo.linalg.lapack_gesdd as lg
use e.algo.linalg.lapack_syevr as ls
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn lehmer(seed: i64, count: usize, out: []f64) {
    var x = (seed * 7919i64 + 12345i64) % 2147483647i64
    var i = 0usize
    while i < count {
        x = (x * 48271i64) % 2147483647i64
        out[i] = f64(x) / 2147483647.0f64
        i += 1usize
    }
}

fn int_of(u: f64, scale: f64, shift: f64) -> f64 { ret math.floor[f64](u * scale) - shift }

fn sym_matrix(a: *mem.Arena, kind: i64, n: usize, seed: i64, out: []f64) -> err {
    let (u, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    lehmer(seed, n * n, u)
    var i = 0usize
    var j = 0usize
    if kind == 0i64 || kind == 1i64 {
        j = 0usize
        while j < n {
            i = 0usize
            while i < n {
                if kind == 0i64 {
                    out[i + j * n] = ((u[i + j * n] - 0.5f64) + (u[j + i * n] - 0.5f64)) / 2.0f64
                } else {
                    out[i + j * n] = int_of(u[i + j * n], 11.0f64, 5.0f64) + int_of(u[j + i * n], 11.0f64, 5.0f64)
                }
                i += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    if kind == 2i64 || kind == 3i64 {
        var r = 2usize
        if kind == 2i64 {
            r = n / 3usize
            if r < 1usize { r = 1usize }
        }
        let (cm, e2) = mem.alloc[f64](a, n * r)
        if e2 != ok { ret e2 }
        lehmer(seed, n * r, cm)
        var k = 0usize
        while k < n * r {
            cm[k] = int_of(cm[k], 7.0f64, 3.0f64)
            k += 1usize
        }
        j = 0usize
        while j < n {
            i = 0usize
            while i < n {
                var sum = 0.0f64
                k = 0usize
                while k < r {
                    sum += cm[i + k * n] * cm[j + k * n]
                    k += 1usize
                }
                if kind == 3i64 && i == j { sum += 3.0f64 }
                out[i + j * n] = sum
                i += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    j = 0usize
    while j < n {
        i = 0usize
        while i < n {
            var v = 0.0f64
            if kind == 4i64 {
                if i == j { v = 2.0f64 }
                if i + 1usize == j || j + 1usize == i { v = -1.0f64 }
            }
            if kind == 5i64 && i == j { v = f64(((i + 1usize) * (i + 1usize)) % 5usize) }
            if kind == 6i64 { v = 1.0f64 }
            out[i + j * n] = v
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

fn gen_matrix(a: *mem.Arena, kind: i64, nr: usize, nc: usize, seed: i64, out: []f64) -> err {
    var i = 0usize
    var j = 0usize
    if kind == 2i64 {
        var mn = nr
        if nc < nr { mn = nc }
        var r = mn / 2usize
        if r < 1usize { r = 1usize }
        let (cm, e1) = mem.alloc[f64](a, nr * r)
        let (dm, e2) = mem.alloc[f64](a, r * nc)
        if e1 != ok || e2 != ok { ret mem.Full }
        lehmer(seed, nr * r, cm)
        lehmer(seed + 1i64, r * nc, dm)
        var k = 0usize
        while k < nr * r {
            cm[k] = int_of(cm[k], 7.0f64, 3.0f64)
            k += 1usize
        }
        k = 0usize
        while k < r * nc {
            dm[k] = int_of(dm[k], 7.0f64, 3.0f64)
            k += 1usize
        }
        j = 0usize
        while j < nc {
            i = 0usize
            while i < nr {
                var sum = 0.0f64
                k = 0usize
                while k < r {
                    sum += cm[i + k * nr] * dm[k + j * r]
                    k += 1usize
                }
                out[i + j * nr] = sum
                i += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    if kind == 3i64 {
        var q = 0usize
        while q < nr * nc {
            out[q] = 0.0f64
            q += 1usize
        }
        var mn = nr
        if nc < nr { mn = nc }
        q = 0usize
        while q < mn {
            out[q + q * nr] = 2.0f64
            q += 1usize
        }
        ret ok
    }
    lehmer(seed, nr * nc, out)
    var q = 0usize
    while q < nr * nc {
        if kind == 1i64 { out[q] = int_of(out[q], 11.0f64, 5.0f64) } else { out[q] = out[q] - 0.5f64 }
        q += 1usize
    }
    if kind == 4i64 {
        q = 0usize
        while q < nr {
            out[q] = 0.0f64
            q += 1usize
        }
    }
    ret ok
}

fn weight(i: usize) -> f64 { ret f64((i * 37usize) % 101usize) / 50.0f64 - 1.0f64 + 0.01f64 }

fn gap(got: f64, want: f64, worst: f64) -> f64 {
    var d = got - want
    if d < 0.0f64 { d = 0.0f64 - d }
    if d != d { ret 1.0e30f64 }
    if d > worst { ret d }
    ret worst
}

fn check_sums(m: []const f64, count: usize, want_sum: f64, want_sq: f64) -> f64 {
    var s = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < count {
        s += m[i]
        q += m[i] * m[i]
        i += 1usize
    }
    var worst = 0.0f64
    var d = s - want_sum
    if d < 0.0f64 { d = 0.0f64 - d }
    if d > 1.0e-9f64 * (1.0f64 + math.abs[f64](want_sum)) { worst = 1.0e9f64 }
    d = q - want_sq
    if d < 0.0f64 { d = 0.0f64 - d }
    if d > 1.0e-9f64 * (1.0f64 + math.abs[f64](want_sq)) { worst = 1.0e9f64 }
    ret worst
}

fn eig_case(a: *mem.Arena, z: []const f64) -> f64 {
    let kind = i64(z[0usize])
    let n = usize(z[1usize])
    let seed = i64(z[2usize])
    let mode = i64(z[3usize])
    let (m, e1) = mem.alloc[f64](a, n * n)
    let (w, e2) = mem.alloc[f64](a, n)
    let (vec, e3) = mem.alloc[f64](a, n * n)
    if e1 != ok || e2 != ok || e3 != ok { ret 1.0e30f64 }
    if sym_matrix(a, kind, n, seed, m) != ok { ret 1.0e30f64 }
    let bad = check_sums(m, n * n, z[4usize], z[5usize])
    if bad > 0.0f64 { ret bad }
    if ls.dsyevr_all(a, m, n, w, vec) != ok { ret 2.0e30f64 }
    var worst = 0.0f64
    var k = 0usize
    while k < n {
        worst = gap(w[n - 1usize - k], z[6usize + k], worst)
        k += 1usize
    }
    k = 0usize
    while k < n {
        let col = n - 1usize - k
        if mode == 0i64 {
            var i = 0usize
            while i < n {
                worst = gap(vec[i + col * n], z[6usize + n + k * n + i], worst)
                i += 1usize
            }
        } else {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += weight(i) * vec[i + col * n]
                i += 1usize
            }
            worst = gap(s, z[6usize + n + k], worst)
        }
        k += 1usize
    }
    ret worst
}

fn svd_case(a: *mem.Arena, z: []const f64) -> f64 {
    let kind = i64(z[0usize])
    let nr = usize(z[1usize])
    let nc = usize(z[2usize])
    let seed = i64(z[3usize])
    let mode = i64(z[4usize])
    var kk = nr
    if nc < nr { kk = nc }
    let (m, e1) = mem.alloc[f64](a, nr * nc)
    let (s, e2) = mem.alloc[f64](a, kk)
    let (u, e3) = mem.alloc[f64](a, nr * kk)
    let (vt, e4) = mem.alloc[f64](a, kk * nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 1.0e30f64 }
    if gen_matrix(a, kind, nr, nc, seed, m) != ok { ret 1.0e30f64 }
    let bad = check_sums(m, nr * nc, z[5usize], z[6usize])
    if bad > 0.0f64 { ret bad }
    if lg.svd_all(a, m, nr, nc, s, u, vt) != ok { ret 2.0e30f64 }
    var worst = 0.0f64
    var k = 0usize
    while k < kk {
        worst = gap(s[k], z[7usize + k], worst)
        k += 1usize
    }
    k = 0usize
    while k < kk {
        if mode == 0i64 {
            var i = 0usize
            while i < nr {
                worst = gap(u[i + k * nr], z[7usize + kk + k * nr + i], worst)
                i += 1usize
            }
            var j = 0usize
            while j < nc {
                worst = gap(vt[k + j * kk], z[7usize + kk + nr * kk + k * nc + j], worst)
                j += 1usize
            }
        } else {
            var su = 0.0f64
            var i = 0usize
            while i < nr {
                su += weight(i) * u[i + k * nr]
                i += 1usize
            }
            worst = gap(su, z[7usize + kk + k], worst)
            var sv = 0.0f64
            var j = 0usize
            while j < nc {
                sv += weight(j) * vt[k + j * kk]
                j += 1usize
            }
            worst = gap(sv, z[7usize + kk + kk + k], worst)
        }
        k += 1usize
    }
    ret worst
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lapack_exact.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        var got = 0.0f64
        if str.eq(c.name, "eig") { got = eig_case(a, c.args) } else { got = svd_case(a, c.args) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 40usize {
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    let _ = str.push(&b, " kind ")
                    let _ = str.push_i64(&b, i64(c.args[0usize]))
                    let _ = str.push(&b, " dims ")
                    let _ = str.push_i64(&b, i64(c.args[1usize]))
                    if str.eq(c.name, "svd") {
                        let _ = str.push(&b, "x")
                        let _ = str.push_i64(&b, i64(c.args[2usize]))
                    }
                    let _ = str.push(&b, " worst gap 1e")
                    var ex = 0i64
                    var g = got
                    if g > 0.0f64 {
                        while g < 1.0f64 && ex > -40i64 {
                            g = g * 10.0f64
                            ex -= 1i64
                        }
                        while g >= 10.0f64 && ex < 40i64 {
                            g = g / 10.0f64
                            ex += 1i64
                        }
                    }
                    let _ = str.push_i64(&b, ex)
                    let _ = str.push(&b, "\n")
                    let _ = io.print(str.done(&b))
                }
            }
        }
        at += 1usize
    }
    let (initial, be) = str.builder(a, 120usize)
    if be == ok {
        var b = initial
        let _ = str.push_i64(&b, i64(failures))
        let _ = str.push(&b, " of ")
        let _ = str.push_i64(&b, i64(golden.cases.len))
        let _ = str.push(&b, " cases differ from R\n")
        let _ = io.print(str.done(&b))
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
