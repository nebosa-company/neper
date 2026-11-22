// R kernlab: kernelMatrix for the rbf, polynomial, linear, tanh, Laplace, ANOVA and spline kernels, and kpca (eigenvalues of the centred kernel matrix divided by n, the scaled eigenvectors pcv and the projections of the training points). Data are row-major, n by p.
//
// Not here: the string kernels, and the Bessel kernel is kernlabmmd.cross kind 7 (ksvm, rvm, gausspr, kfa, specc, ranking, ipop and kmmd live in the kernlab* modules).

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.armld as ld
use e.math
use e.mem

// kind 0 rbfdot(par1 = sigma), 1 polydot(par1 = degree, par2 = scale, par3 = offset), 2 vanilladot, 3 tanhdot(par1 = scale, par2 = offset), 4 laplacedot(par1 = sigma), 5 anovadot(par1 = sigma, par2 = degree), 6 splinedot
fn kernel(kind: usize, x: []const f64, y: []const f64, par1: f64, par2: f64, par3: f64) -> f64 {
    var dot = 0.0f64
    var d2 = 0.0f64
    var i = 0usize
    while i < x.len {
        dot += x[i] * y[i]
        d2 += (x[i] - y[i]) * (x[i] - y[i])
        i += 1usize
    }
    if kind == 0usize { ret math.exp[f64](0.0f64 - par1 * d2) }
    if kind == 1usize { ret math.pow[f64](par2 * dot + par3, par1) }
    if kind == 2usize { ret dot }
    if kind == 3usize {
        let e2 = math.exp[f64](2.0f64 * (par1 * dot + par2))
        ret (e2 - 1.0f64) / (e2 + 1.0f64)
    }
    if kind == 4usize { ret math.exp[f64](0.0f64 - par1 * math.sqrt[f64](d2)) }
    if kind == 5usize {
        var s = 0.0f64
        i = 0usize
        while i < x.len {
            s += math.exp[f64](0.0f64 - par1 * (x[i] - y[i]) * (x[i] - y[i]))
            i += 1usize
        }
        ret math.pow[f64](s, par2)
    }
    var prod = 1.0f64
    i = 0usize
    while i < x.len {
        var mn = x[i]
        if y[i] < mn { mn = y[i] }
        prod *= 1.0f64 + x[i] * y[i] + x[i] * y[i] * mn - (x[i] + y[i]) / 2.0f64 * mn * mn + mn * mn * mn / 3.0f64
        i += 1usize
    }
    ret prod
}

fn kernel_matrix(kind: usize, x: []const f64, n: usize, p: usize, par1: f64, par2: f64, par3: f64, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = kernel(kind, x[i * p..(i + 1usize) * p], x[j * p..(j + 1usize) * p], par1, par2, par3)
            j += 1usize
        }
        i += 1usize
    }
}

// kpca with k features of the kernel matrix kk (n by n), as kpca.R does it: kc = t(t(km - colSums(km) / n) - rowSums(km) / n) + sum(km) / n^2 with R's long-double sums,
// eigen(kc / n) by LAPACK dsyevr (lower triangle), eig (k) its top eigenvalues, pcv (n by k) = vectors / sqrt(eig), rotated (n by k) = kc %*% pcv. Signs are LAPACK's, as R returns them.
fn kpca(a: *mem.Arena, kk: []const f64, n: usize, k: usize, eig: []f64, pcv: []f64, rotated: []f64) -> err {
    let nf = f64(n)
    let (kc, e1) = mem.alloc[f64](a, n * n)
    let (cs, e2) = mem.alloc[f64](a, n)
    let (rs, e3) = mem.alloc[f64](a, n)
    let (xc, e4) = mem.alloc[f64](a, n * n)
    let (w, e5) = mem.alloc[f64](a, n)
    let (z, e6) = mem.alloc[f64](a, n * n)
    let (col, e7) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            col[j] = kk[j * n + i]
            j += 1usize
        }
        cs[i] = ld.sum_ld(col[0usize..n])
        rs[i] = ld.sum_ld(kk[i * n..(i + 1usize) * n])
        i += 1usize
    }
    let tot = ld.sum_ld(kk[0usize..n * n])
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            kc[i * n + j] = ((kk[i * n + j] - cs[i] / nf) - rs[j] / nf) + tot / (nf * nf)
            xc[i + j * n] = kc[i * n + j] / nf
            j += 1usize
        }
        i += 1usize
    }
    let r = sy.dsyevr_all(a, xc, n, w, z)
    if r != ok { ret r }
    var c = 0usize
    while c < k {
        eig[c] = w[n - 1usize - c]
        i = 0usize
        while i < n {
            pcv[i * k + c] = z[(n - 1usize - c) * n + i] / math.sqrt[f64](eig[c])
            i += 1usize
        }
        c += 1usize
    }
    i = 0usize
    while i < n {
        c = 0usize
        while c < k {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                s += kc[i * n + j] * pcv[j * k + c]
                j += 1usize
            }
            rotated[i * k + c] = s
            c += 1usize
        }
        i += 1usize
    }
    ret ok
}
