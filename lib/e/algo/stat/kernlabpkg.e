// R kernlab: kernelMatrix for the rbf, polynomial, linear, tanh, Laplace, ANOVA and spline kernels, and kpca (eigenvalues of the centred kernel matrix divided by n, the scaled eigenvectors pcv and the projections of the training points). Data are row-major, n by p. Axis signs are free.
//
// Not here: the Bessel and string kernels, ksvm, ksvm-based classifiers, rvm, gausspr, kernel k-means, spectral clustering, kfa, ipop.

use e.algo.linalg.matrix as mx
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

// kpca with k features of the kernel matrix kk (n by n): eig (k) = eigenvalues of the centred matrix over n, pcv (n by k) = vectors / sqrt(eig), rotated (n by k) = centred matrix times pcv
fn kpca(a: *mem.Arena, kk: []const f64, n: usize, k: usize, eig: []f64, pcv: []f64, rotated: []f64) -> err {
    let nf = f64(n)
    let (kc, e1) = mem.alloc[f64](a, n * n)
    let (rm, e2) = mem.alloc[f64](a, n)
    let (vv, e3) = mem.alloc[f64](a, n * n)
    let (ev, e4) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        rm[i] = 0.0f64
        var j = 0usize
        while j < n {
            rm[i] += kk[i * n + j] / nf
            j += 1usize
        }
        tot += rm[i] / nf
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            kc[i * n + j] = kk[i * n + j] - rm[i] - rm[j] + tot
            j += 1usize
        }
        i += 1usize
    }
    let (vm, e5) = mx.view[f64](vv, n, n, n)
    let (src, e6) = mx.view_const[f64](kc, n, n, n)
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    let r = mx.eigen(a, ev, vm, src, 1.0e-14f64, 200u32)
    if r != ok { ret r }
    var c = 0usize
    while c < k {
        eig[c] = ev[c] / nf
        i = 0usize
        while i < n {
            pcv[i * k + c] = vv[i * n + c] / math.sqrt[f64](eig[c])
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
