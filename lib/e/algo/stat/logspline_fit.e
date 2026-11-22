// R polspline logspline fitting: the knot search of the package's nlsd.c (the engine behind logspline()). A log
// density that is a cubic spline in the truncated power basis, fitted by Newton-Raphson with exact integrals; knots
// are added one at a time at the best Rao statistic (found by interval halving between the data points), then removed
// one at a time at the smallest Wald statistic, and the model with the smallest AIC (penalty * dimension - 2 logl)
// wins. Not here: oldlogspline (lsdall.c), the silent trace, error.action = 2's re-run.

use e.math
use e.mem

const MK: i64 = 60i64
const MK5: usize = 65usize
const LS: usize = 141usize

error Invalid
error Failed

// one model (struct space): the basis functions are stored side by side, c1 per function MK5 wide, c2 per function kk by 4
type Sp = struct {
    ndim: i64, nk: i64, nip: i64, ilow: i64, iupp: i64, aic: f64, low: f64, upp: f64, cth: f64, kk: usize,
    iknots: []i64, knots: []f64, info: []f64, score: []f64, ips: []f64,
    beta: []f64, c1: []f64, c2: []f64, sumunc: []f64, c3: []i64, iks: []i64
}

type S = struct {
    nd: i64, kk: usize, ctheta: f64, xxa: f64,
    data: []f64, same: []i64, idata: []i64,
    cuu: []f64, kints: []f64,
    ww6: []f64, yy6: []f64, ww7: []f64, yy7: []f64,
    getiips: []i64, luwi: []i64, rearix: []i64,
    fiveee: []f64, fiveh1: []f64, fiverr: []f64, betaaddv1: []f64, betaremr1: []f64, raoss: []f64,
    luw: []f64, luw2: []f64, luww: []f64, itertmp1: []f64, itertmp2: []f64, rearsorted: []f64,
    solc1: []f64, solc2: []f64, solc3: []f64, itertmp3: []f64, pompcoef: []f64, betaaddt1: []f64,
    raoii: []f64, raoc2: []f64, betaremm2: []f64, betaaddsorted: []f64,
    rc3: []i64, rsum: f64, tcoef: []f64, trrr: []f64, tintext: []f64, tc2ext: []f64, tint2ext: []f64, tb3: []f64
}

fn zf(a: *mem.Arena, n: usize) -> ([]f64, err) {
    let (v, e) = mem.alloc[f64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0.0f64
        i += 1usize
    }
    ret (v, ok)
}

fn zi(a: *mem.Arena, n: usize) -> ([]i64, err) {
    let (v, e) = mem.alloc[i64](a, n)
    if e != ok { ret (v, e) }
    var i = 0usize
    while i < n {
        v[i] = 0
        i += 1usize
    }
    ret (v, ok)
}

fn u(i: i64) -> usize { ret usize(i) }

fn newsp(a: *mem.Arena, kk: usize) -> (Sp, err) {
    var p: Sp = zero
    p.kk = kk
    p.aic = math.pow[f64](10.0f64, 100.0f64)
    let (ik, e1) = zi(a, MK5 + 1usize)
    let (kn, e2) = zf(a, MK5 + 1usize)
    let (sc, e3) = zf(a, MK5 + 1usize)
    let (inf, e4) = zf(a, (MK5 + 1usize) * (MK5 + 1usize))
    let (ip, e5) = zf(a, kk + 1usize)
    let (be, e6) = zf(a, MK5)
    let (c1, e7) = zf(a, MK5 * (MK5 + 1usize))
    let (c2, e8) = zf(a, MK5 * (kk + 1usize) * 4usize)
    let (su, e9) = zf(a, MK5)
    let (c3, e10) = zi(a, MK5 * 2usize)
    let (iks, e11) = zi(a, MK5 * 5usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (p, mem.Full) }
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (p, mem.Full) }
    p.iknots = ik
    p.knots = kn
    p.score = sc
    p.info = inf
    p.ips = ip
    p.beta = be
    p.c1 = c1
    p.c2 = c2
    p.sumunc = su
    p.c3 = c3
    p.iks = iks
    p.nip = i64(kk)
    ret (p, ok)
}

fn ii(i: i64, j: i64) -> usize { ret u(i) * MK5 + u(j) }
fn c1i(b: i64, j: i64) -> usize { ret u(b) * MK5 + u(j) }
fn c2i(p: *Sp, b: i64, j: i64, k: usize) -> usize { ret (u(b) * (p.kk + 1usize) + u(j)) * 4usize + k }

fn makes(a: *mem.Arena, data: []const f64, nd: usize) -> (S, err) {
    var w: S = zero
    w.nd = i64(nd)
    w.kk = usize(MK) + 10usize + nd / 100usize + 300usize
    let kk = w.kk
    let (d, e0) = zf(a, nd + 1usize)
    var i = 0usize
    while i < nd {
        d[i] = data[i]
        i += 1usize
    }
    w.data = d
    let (sm, e1) = zi(a, nd + 2usize)
    let (idt, e2) = zi(a, nd + 2usize)
    let (cu, e3) = zf(a, MK5 + 1usize)
    let (ki, e4) = zf(a, (kk + 10usize) * 7usize)
    let (w6, e5) = zf(a, 8usize)
    let (y6, e6) = zf(a, 8usize)
    let (w7, e7) = zf(a, 40usize)
    let (y7, e8) = zf(a, 40usize)
    let (gi, e9) = zi(a, kk + 12usize)
    let (lwi, e10) = zi(a, 2usize * usize(MK) + 22usize)
    let (rx, e11) = zi(a, nd + 2usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (w, mem.Full) }
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret (w, mem.Full) }
    w.same = sm
    w.idata = idt
    w.cuu = cu
    w.kints = ki
    w.ww6 = w6
    w.yy6 = y6
    w.ww7 = w7
    w.yy7 = y7
    w.getiips = gi
    w.luwi = lwi
    w.rearix = rx
    let big = nd + usize(MK) * 2usize + 20usize
    let (f1, g1) = zf(a, big)
    let (f2, g2) = zf(a, big)
    let (f3, g3) = zf(a, big)
    let (f4, g4) = zf(a, big)
    let (f5, g5) = zf(a, big)
    let (f6, g6) = zf(a, big)
    let (f7, g7) = zf(a, big)
    let (f8, g8) = zf(a, big)
    let (f9, g9) = zf(a, big)
    if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok { ret (w, mem.Full) }
    w.fiverr = f1
    w.fiveee = f2
    w.fiveh1 = f3
    w.betaaddv1 = f4
    w.betaremr1 = f5
    w.raoss = f6
    w.itertmp1 = f7
    w.itertmp2 = f8
    w.rearsorted = f9
    let (l1, h1) = zf(a, 2usize * usize(MK) + 22usize)
    let (l2, h2) = zf(a, 2usize * usize(MK) + 22usize)
    let (l3, h3) = zf(a, LS * LS)
    if h1 != ok || h2 != ok || h3 != ok { ret (w, mem.Full) }
    w.luw = l1
    w.luw2 = l2
    w.luww = l3
    let msq = (MK5 + 1usize) * (MK5 + 1usize)
    let (m1, n1) = zf(a, msq)
    let (m2, n2) = zf(a, msq)
    let (m3, n3) = zf(a, msq)
    let (m4, n4) = zf(a, msq)
    let (m5, n5) = zf(a, msq)
    let (m6, n6) = zf(a, msq)
    let (m7, n7) = zf(a, msq)
    let (m8, n8) = zf(a, (kk + 4usize) * 4usize)
    let (m9, n9) = zf(a, (kk + 12usize) * 4usize)
    if n1 != ok || n2 != ok || n3 != ok || n4 != ok || n5 != ok || n6 != ok || n7 != ok || n8 != ok || n9 != ok { ret (w, mem.Full) }
    w.solc1 = m1
    w.solc2 = m2
    w.solc3 = m3
    w.itertmp3 = m4
    w.betaaddt1 = m5
    w.raoii = m6
    w.betaremm2 = m7
    w.pompcoef = m8
    w.raoc2 = m9
    let (bs, e12) = zf(a, nd + 2usize)
    let (r3, e13) = zi(a, 4usize)
    let (t1, e14) = zf(a, 12usize)
    let (t2, e15) = zf(a, 12usize)
    let (t3, e16) = zf(a, 12usize)
    let (t4, e17) = zf(a, 12usize)
    let (t5, e18) = zf(a, 12usize)
    let (t6, e19) = zf(a, 12usize)
    if e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret (w, mem.Full) }
    w.betaaddsorted = bs
    w.rc3 = r3
    w.tcoef = t1
    w.trrr = t2
    w.tintext = t3
    w.tc2ext = t4
    w.tint2ext = t5
    w.tb3 = t6
    // Gaussian quadrature coefficients
    w.ww6[1usize] = 0.467913934572691f64
    w.yy6[1usize] = 0.238619186083197f64
    w.ww6[2usize] = 0.360761573048139f64
    w.yy6[2usize] = 0.661209386466265f64
    w.ww6[3usize] = 0.171324429379170f64
    w.yy6[3usize] = 0.932469514203152f64
    w.ww7[1usize] = 0.00178328072169643f64
    w.yy7[1usize] = 0.99930504173577217f64
    w.ww7[2usize] = 0.00414703326056247f64
    w.yy7[2usize] = 0.99634011677195533f64
    w.ww7[3usize] = 0.00650445796897836f64
    w.yy7[3usize] = 0.99101337147674429f64
    w.ww7[4usize] = 0.00884675982636395f64
    w.yy7[4usize] = 0.98333625388462598f64
    w.ww7[5usize] = 0.01116813946013113f64
    w.yy7[5usize] = 0.97332682778991098f64
    w.ww7[6usize] = 0.01346304789671864f64
    w.yy7[6usize] = 0.96100879965205377f64
    w.ww7[7usize] = 0.01572603047602472f64
    w.yy7[7usize] = 0.94641137485840277f64
    w.ww7[8usize] = 0.01795171577569734f64
    w.yy7[8usize] = 0.92956917213193957f64
    w.ww7[9usize] = 0.02013482315353021f64
    w.yy7[9usize] = 0.91052213707850282f64
    w.ww7[10usize] = 0.02227017380838325f64
    w.yy7[10usize] = 0.88931544599511414f64
    w.ww7[11usize] = 0.02435270256871087f64
    w.yy7[11usize] = 0.86599939815409277f64
    w.ww7[12usize] = 0.02637746971505466f64
    w.yy7[12usize] = 0.84062929625258032f64
    w.ww7[13usize] = 0.02833967261425948f64
    w.yy7[13usize] = 0.81326531512279754f64
    w.ww7[14usize] = 0.03023465707240248f64
    w.yy7[14usize] = 0.78397235894334139f64
    w.ww7[15usize] = 0.03205792835485155f64
    w.yy7[15usize] = 0.75281990726053194f64
    w.ww7[16usize] = 0.03380516183714161f64
    w.yy7[16usize] = 0.71988185017161088f64
    w.ww7[17usize] = 0.03547221325688239f64
    w.yy7[17usize] = 0.68523631305423327f64
    w.ww7[18usize] = 0.03705512854024005f64
    w.yy7[18usize] = 0.64896547125465731f64
    w.ww7[19usize] = 0.03855015317861563f64
    w.yy7[19usize] = 0.61115535517239328f64
    w.ww7[20usize] = 0.03995374113272034f64
    w.yy7[20usize] = 0.57189564620263400f64
    w.ww7[21usize] = 0.04126256324262353f64
    w.yy7[21usize] = 0.53127946401989457f64
    w.ww7[22usize] = 0.04247351512365359f64
    w.yy7[22usize] = 0.48940314570705296f64
    w.ww7[23usize] = 0.04358372452932345f64
    w.yy7[23usize] = 0.44636601725346409f64
    w.ww7[24usize] = 0.04459055816375657f64
    w.yy7[24usize] = 0.40227015796399163f64
    w.ww7[25usize] = 0.04549162792741814f64
    w.yy7[25usize] = 0.35722015833766813f64
    w.ww7[26usize] = 0.04628479658131442f64
    w.yy7[26usize] = 0.31132287199021097f64
    w.ww7[27usize] = 0.04696818281621002f64
    w.yy7[27usize] = 0.26468716220876742f64
    w.ww7[28usize] = 0.04754016571483031f64
    w.yy7[28usize] = 0.21742364374000708f64
    w.ww7[29usize] = 0.04799938859645831f64
    w.yy7[29usize] = 0.16964442042399283f64
    w.ww7[30usize] = 0.04834476223480295f64
    w.yy7[30usize] = 0.12146281929612056f64
    w.ww7[31usize] = 0.04857546744150343f64
    w.yy7[31usize] = 0.07299312178779904f64
    w.ww7[32usize] = 0.04869095700913972f64
    w.yy7[32usize] = 0.02435029266342443f64
    ret (w, ok)
}

fn mylog(x: f64) -> f64 {
    if x < 10.0e-250f64 { ret 0.0f64 - 575.64627f64 }
    ret math.log[f64](x)
}

fn myexp(x: f64) -> f64 {
    if x > 576.0f64 { ret math.exp[f64](576.0f64) }
    ret math.exp[f64](x)
}

fn fabs(x: f64) -> f64 { ret math.abs[f64](x) }

// --- LU (Numerical Recipes, 1-based inside luww with stride LS)

fn lu(i: usize, j: usize) -> usize { ret i * LS + j }

fn ludcmp(w: *S, n: usize, indx: []i64) -> bool {
    let a = w.luww
    let vv = w.luw
    var i = 0usize
    while i <= n + 1usize {
        vv[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i <= n {
        var big = 0.0f64
        var j = 1usize
        while j <= n {
            let temp = fabs(a[lu(i, j)])
            if temp > big { big = temp }
            j += 1usize
        }
        if big == 0.0f64 { ret false }
        vv[i] = 1.0f64 / big
        i += 1usize
    }
    var imax = 0usize
    var j = 1usize
    while j <= n {
        i = 1usize
        while i < j {
            var sum = a[lu(i, j)]
            var k = 1usize
            while k < i {
                sum = sum - a[lu(i, k)] * a[lu(k, j)]
                k += 1usize
            }
            a[lu(i, j)] = sum
            i += 1usize
        }
        var big = 0.0f64
        i = j
        while i <= n {
            var sum = a[lu(i, j)]
            var k = 1usize
            while k < j {
                sum = sum - a[lu(i, k)] * a[lu(k, j)]
                k += 1usize
            }
            a[lu(i, j)] = sum
            let dum = vv[i] * fabs(sum)
            if dum >= big {
                big = dum
                imax = i
            }
            i += 1usize
        }
        if j != imax {
            var k = 1usize
            while k <= n {
                let dum = a[lu(imax, k)]
                a[lu(imax, k)] = a[lu(j, k)]
                a[lu(j, k)] = dum
                k += 1usize
            }
            vv[imax] = vv[j]
        }
        indx[j] = i64(imax)
        if a[lu(j, j)] == 0.0f64 { a[lu(j, j)] = 1.0e-20f64 }
        if j != n {
            let dum = 1.0f64 / a[lu(j, j)]
            i = j + 1usize
            while i <= n {
                a[lu(i, j)] = a[lu(i, j)] * dum
                i += 1usize
            }
        }
        j += 1usize
    }
    ret true
}

// b[i - sh] is the i-th (1-based) element
fn lubksb(w: *S, n: usize, indx: []i64, b: []f64, sh: usize) {
    let a = w.luww
    var iz = 0usize
    var i = 1usize
    while i <= n {
        let ip = usize(indx[i])
        var sum = b[ip - sh]
        b[ip - sh] = b[i - sh]
        if iz > 0usize {
            var j = iz
            while j <= i - 1usize {
                sum = sum - a[lu(i, j)] * b[j - sh]
                j += 1usize
            }
        } else {
            if sum != 0.0f64 { iz = i }
        }
        b[i - sh] = sum
        i += 1usize
    }
    i = n
    while i >= 1usize {
        var sum = b[i - sh]
        var j = i + 1usize
        while j <= n {
            sum = sum - a[lu(i, j)] * b[j - sh]
            j += 1usize
        }
        b[i - sh] = sum / a[lu(i, i)]
        i = i - 1usize
    }
}

// a is n by n with stride MK5; replaced by its inverse
fn luinverse(w: *S, a: []f64, n: usize) {
    let c = w.luww
    let d = w.luw2
    let idx = w.luwi
    var j = 1usize
    while j <= n {
        var k = 1usize
        while k <= n {
            c[lu(j, k)] = a[(j - 1usize) * MK5 + (k - 1usize)]
            k += 1usize
        }
        j += 1usize
    }
    let okk = ludcmp(w, n, idx)
    j = 1usize
    while j <= n {
        var k = 1usize
        while k <= n {
            d[k] = 0.0f64
            k += 1usize
        }
        d[j] = 1.0f64
        lubksb(w, n, idx, d, 0usize)
        k = 1usize
        while k <= n {
            a[(k - 1usize) * MK5 + (j - 1usize)] = d[k]
            k += 1usize
        }
        j += 1usize
    }
}

// solves a x = b (b overwritten); false when singular
fn lusolve2(w: *S, a: []f64, n: usize, b: []f64) -> bool {
    let c = w.luww
    let idx = w.luwi
    var j = 0usize
    while j < n + 1usize {
        idx[j] = 0
        j += 1usize
    }
    j = 0usize
    while j < n {
        var k = 0usize
        while k < n {
            c[lu(j + 1usize, k + 1usize)] = a[j * MK5 + k]
            k += 1usize
        }
        j += 1usize
    }
    if !ludcmp(w, n, idx) { ret false }
    lubksb(w, n, idx, b, 1usize)
    ret true
}

// --- integrals (results written at r[ro..], coefficients at cf[co..])

fn fctf1(b0: f64, b1: f64, t1: f64, f1: f64, j0: i64) -> f64 {
    var j = j0
    if f1 < 0.0f64 { j = 0i64 - j }
    var g = mylog(fabs(f1)) + b1 * t1 + b0
    if g > 600.0f64 { g = 600.0f64 }
    ret f64(j) * myexp(g)
}

fn fctf2(b0: f64, b1: f64, t1: f64, t2: f64, f1: f64, f2: f64) -> f64 {
    var i1 = 1i64
    var i2 = 1i64
    if f1 < 0.0f64 { i1 = 0i64 - 1i64 }
    var g1 = mylog(fabs(f1)) + b1 * t1 + b0
    if g1 > 600.0f64 { g1 = 600.0f64 }
    if f2 < 0.0f64 { i2 = 0i64 - 1i64 }
    var g2 = mylog(fabs(f2)) + b1 * t2 + b0
    if g2 > 600.0f64 { g2 = 600.0f64 }
    ret f64(i2) * myexp(g2) - f64(i1) * myexp(g1)
}

fn pol3(c: []f64, co: usize, x: f64) -> f64 {
    ret c[co] + x * (c[co + 1usize] + x * (c[co + 2usize] + x * c[co + 3usize]))
}

fn inp3(c1: []f64, o1: usize, c2: []f64, o2: usize) -> f64 {
    ret c1[o1] * c2[o2] + c1[o1 + 1usize] * c2[o2 + 1usize] + c1[o1 + 2usize] * c2[o2 + 2usize] + c1[o1 + 3usize] * c2[o2 + 3usize]
}

fn mat3(c1: []f64, o1: usize, c2: []f64, o2: usize, c3: []f64, o3: usize) -> f64 {
    var x = 0.0f64
    var i = 0usize
    while i < 4usize {
        var j = 0usize
        while j < 4usize {
            x = x + c1[o1 + i + j] * c2[o2 + i] * c3[o3 + j]
            j += 1usize
        }
        i += 1usize
    }
    ret x
}

// integrals of x^i exp(polynomial) over (k1, k2), by Gauss-Legendre (what 0: only i = 0)
fn m1int(w: *S, vv: []f64, vo: usize, k1: f64, k2: f64, what: i64, cf: []f64, co: usize, accuracy: i64) {
    let r1 = (k2 - k1) / 2.0f64
    let r2 = (k2 + k1) / 2.0f64
    var i1 = 0usize
    while i1 < 7usize {
        vv[vo + i1] = 0.0f64
        i1 += 1usize
    }
    if k2 == k1 { ret }
    var jj = 7usize
    if what == 0 { jj = 1usize }
    var np = 33usize
    if accuracy == 1 { np = 4usize }
    i1 = 1usize
    while i1 < np {
        var yv = w.yy7[i1]
        var wv = w.ww7[i1]
        if accuracy == 1 {
            yv = w.yy6[i1]
            wv = w.ww6[i1]
        }
        let y = yv * r1
        let v = r1 * wv
        var side = 0usize
        while side < 2usize {
            var x = r2 - y
            if side == 1usize { x = r2 + y }
            var z = v * myexp(cf[co] + x * (cf[co + 1usize] + x * (cf[co + 2usize] + x * cf[co + 3usize])))
            vv[vo] = vv[vo] + z
            var i2 = 1usize
            while i2 < jj {
                z = z * x
                vv[vo + i2] = vv[vo + i2] + z
                i2 += 1usize
            }
            side += 1usize
        }
        i1 += 1usize
    }
}

// -inf to t1 (j = 1) or t1 to inf (j = -1)
fn l1int(r: []f64, ro: usize, t1: f64, cf: []f64, co: usize, j: i64, what: i64) {
    let b1 = cf[co + 1usize]
    let b0 = cf[co]
    let b3 = r
    // powers of 1/b1 kept in a local array through the result slots would clash, so compute them inline
    let p0 = 1.0f64 / b1
    let p1 = p0 * p0
    let p2 = p1 * p0
    let p3 = p2 * p0
    let p4 = p3 * p0
    let p5 = p4 * p0
    let p6 = p5 * p0
    r[ro] = fctf1(b0, b1, t1, p0, j)
    if what == 0 { ret }
    var u0 = 0.0f64 - p1
    var f1 = p0 * t1 + u0
    r[ro + 1usize] = fctf1(b0, b1, t1, f1, j)

    var u1 = 0.0f64 - 2.0f64 * p1
    u0 = 2.0f64 * p2
    f1 = (p0 * t1 + u1) * t1 + u0
    r[ro + 2usize] = fctf1(b0, b1, t1, f1, j)

    var u2 = 0.0f64 - 3.0f64 * p1
    u1 = 6.0f64 * p2
    u0 = 0.0f64 - 6.0f64 * p3
    f1 = ((p0 * t1 + u2) * t1 + u1) * t1 + u0
    r[ro + 3usize] = fctf1(b0, b1, t1, f1, j)

    var u3 = 0.0f64 - 4.0f64 * p1
    u2 = 12.0f64 * p2
    u1 = 0.0f64 - 24.0f64 * p3
    u0 = 24.0f64 * p4
    f1 = (((p0 * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
    r[ro + 4usize] = fctf1(b0, b1, t1, f1, j)

    var u4 = 0.0f64 - 5.0f64 * p1
    u3 = 20.0f64 * p2
    u2 = 0.0f64 - 60.0f64 * p3
    u1 = 120.0f64 * p4
    u0 = 0.0f64 - 120.0f64 * p5
    f1 = ((((p0 * t1 + u4) * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
    r[ro + 5usize] = fctf1(b0, b1, t1, f1, j)

    var u5 = 0.0f64 - 6.0f64 * p1
    u4 = 30.0f64 * p2
    u3 = 0.0f64 - 120.0f64 * p3
    u2 = 360.0f64 * p4
    u1 = 0.0f64 - 720.0f64 * p5
    u0 = 720.0f64 * p6
    f1 = (((((p0 * t1 + u5) * t1 + u4) * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
    r[ro + 6usize] = fctf1(b0, b1, t1, f1, j)
}

// t1 to t2, exactly
fn l2int(r: []f64, ro: usize, t1: f64, t2: f64, cf: []f64, co: usize, what: i64) {
    var b0 = cf[co]
    let b1 = cf[co + 1usize]
    if b1 != 0.0f64 {
        let p0 = 1.0f64 / b1
        let p1 = p0 * p0
        let p2 = p1 * p0
        let p3 = p2 * p0
        let p4 = p3 * p0
        let p5 = p4 * p0
        let p6 = p5 * p0
        r[ro] = fctf2(b0, b1, t1, t2, p0, p0)
        if what == 0 { ret }
        var u1 = p0
        var u0 = 0.0f64 - p1
        var f1 = u1 * t1 + u0
        var f2 = u1 * t2 + u0
        r[ro + 1usize] = fctf2(b0, b1, t1, t2, f1, f2)

        var u2 = p0
        u1 = 0.0f64 - 2.0f64 * p1
        u0 = 2.0f64 * p2
        f1 = (u2 * t1 + u1) * t1 + u0
        f2 = (u2 * t2 + u1) * t2 + u0
        r[ro + 2usize] = fctf2(b0, b1, t1, t2, f1, f2)

        var u3 = p0
        u2 = 0.0f64 - 3.0f64 * p1
        u1 = 6.0f64 * p2
        u0 = 0.0f64 - 6.0f64 * p3
        f1 = ((u3 * t1 + u2) * t1 + u1) * t1 + u0
        f2 = ((u3 * t2 + u2) * t2 + u1) * t2 + u0
        r[ro + 3usize] = fctf2(b0, b1, t1, t2, f1, f2)

        var u4 = p0
        u3 = 0.0f64 - 4.0f64 * p1
        u2 = 12.0f64 * p2
        u1 = 0.0f64 - 24.0f64 * p3
        u0 = 24.0f64 * p4
        f1 = (((u4 * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
        f2 = (((u4 * t2 + u3) * t2 + u2) * t2 + u1) * t2 + u0
        r[ro + 4usize] = fctf2(b0, b1, t1, t2, f1, f2)

        var u5 = p0
        u4 = 0.0f64 - 5.0f64 * p1
        u3 = 20.0f64 * p2
        u2 = 0.0f64 - 60.0f64 * p3
        u1 = 120.0f64 * p4
        u0 = 0.0f64 - 120.0f64 * p5
        f1 = ((((u5 * t1 + u4) * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
        f2 = ((((u5 * t2 + u4) * t2 + u3) * t2 + u2) * t2 + u1) * t2 + u0
        r[ro + 5usize] = fctf2(b0, b1, t1, t2, f1, f2)

        var u6 = p0
        u5 = 0.0f64 - 6.0f64 * p1
        u4 = 30.0f64 * p2
        u3 = 0.0f64 - 120.0f64 * p3
        u2 = 360.0f64 * p4
        u1 = 0.0f64 - 720.0f64 * p5
        u0 = 720.0f64 * p6
        f1 = (((((u6 * t1 + u5) * t1 + u4) * t1 + u3) * t1 + u2) * t1 + u1) * t1 + u0
        f2 = (((((u6 * t2 + u5) * t2 + u4) * t2 + u3) * t2 + u2) * t2 + u1) * t2 + u0
        r[ro + 6usize] = fctf2(b0, b1, t1, t2, f1, f2)
        ret
    }
    b0 = myexp(b0)
    r[ro] = (t2 - t1) * b0
    if what == 0 { ret }
    var f2 = t2
    var f1 = t1
    var i = 1usize
    while i < 7usize {
        f2 = f2 * t2
        f1 = f1 * t1
        r[ro + i] = b0 * (f2 - f1) / f64(i + 1usize)
        i += 1usize
    }
}

// --- copying a model

fn swapspace(s1: *Sp, s2: *Sp) {
    s1.ndim = s2.ndim
    s1.nk = s2.nk
    s1.cth = s2.cth
    s1.nip = s2.nip
    s1.aic = s2.aic
    s1.low = s2.low
    s1.upp = s2.upp
    s1.ilow = s2.ilow
    s1.iupp = s2.iupp
    var i = 0i64
    while i < s1.nip {
        s1.ips[u(i)] = s2.ips[u(i)]
        i += 1i64
    }
    i = 0i64
    while i < s1.nk {
        s1.knots[u(i)] = s2.knots[u(i)]
        s1.iknots[u(i)] = s2.iknots[u(i)]
        i += 1i64
    }
    i = 0i64
    while i < s1.ndim {
        var j = 0usize
        while j < 5usize {
            s1.iks[u(i) * 5usize + j] = s2.iks[u(i) * 5usize + j]
            j += 1usize
        }
        s1.score[u(i)] = s2.score[u(i)]
        var jj = 0i64
        while jj < s1.ndim {
            s1.info[ii(i, jj)] = s2.info[ii(i, jj)]
            jj += 1i64
        }
        s1.beta[u(i)] = s2.beta[u(i)]
        j = 0usize
        while j < 2usize {
            s1.c3[u(i) * 2usize + j] = s2.c3[u(i) * 2usize + j]
            j += 1usize
        }
        s1.sumunc[u(i)] = s2.sumunc[u(i)]
        jj = 0i64
        while jj < s1.nk + 2i64 {
            s1.c1[c1i(i, jj)] = s2.c1[c1i(i, jj)]
            jj += 1i64
        }
        j = 0usize
        while j < 4usize {
            var k = 0i64
            while k < s1.nip {
                s1.c2[c2i(s1, i, k, j)] = s2.c2[c2i(s2, i, k, j)]
                k += 1i64
            }
            j += 1usize
        }
        i += 1i64
    }
}

// --- log-likelihood, score and Hessian

fn savecode1(w: *S, p: *Sp, j: i64) {
    var k = 0i64
    while k < p.ndim {
        if j >= p.c3[u(k) * 2usize] && j <= p.c3[u(k) * 2usize + 1usize] {
            p.score[u(k)] = p.score[u(k)] + inp3(w.kints, u(j) * 7usize, p.c2, c2i(p, k, j, 0usize))
            var j2 = 0i64
            while j2 <= k {
                if j >= p.c3[u(j2) * 2usize] && j <= p.c3[u(j2) * 2usize + 1usize] {
                    p.info[ii(k, j2)] = p.info[ii(k, j2)] + mat3(w.kints, u(j) * 7usize, p.c2, c2i(p, k, j, 0usize), p.c2, c2i(p, j2, j, 0usize))
                }
                j2 += 1i64
            }
        }
        k += 1i64
    }
}

fn pompall(w: *S, p: *Sp, what: i64, xp: *i64) -> f64 {
    let nip = p.nip
    let ndim = p.ndim
    let coef = w.pompcoef
    let ips = p.ips
    var i = 0i64
    while i < nip - 1i64 {
        var j = 0usize
        while j < 4usize {
            coef[u(i) * 4usize + j] = 0.0f64
            var k = 0i64
            while k < ndim {
                coef[u(i) * 4usize + j] = coef[u(i) * 4usize + j] + p.beta[u(k)] * p.c2[c2i(p, k, i, j)]
                k += 1i64
            }
            j += 1usize
        }
        i += 1i64
    }
    if p.ilow == 1 {
        l1int(w.kints, 0usize, ips[1usize], coef, 0usize, 1, what)
    } else {
        l2int(w.kints, 0usize, p.low, ips[1usize], coef, 0usize, what)
    }
    i = 1i64
    while i < nip - 2i64 {
        m1int(w, w.kints, u(i) * 7usize, ips[u(i)], ips[u(i + 1i64)], what, coef, u(i) * 4usize, 0)
        i += 1i64
    }
    if p.iupp == 1 {
        l1int(w.kints, u(nip - 2i64) * 7usize, ips[u(nip - 2i64)], coef, u(nip - 2i64) * 4usize, 0 - 1, what)
    } else {
        l2int(w.kints, u(nip - 2i64) * 7usize, ips[u(nip - 2i64)], p.upp, coef, u(nip - 2i64) * 4usize, what)
    }
    var ct = 0.0f64
    i = 0i64
    while i < nip - 1i64 {
        ct = ct + w.kints[u(i) * 7usize]
        i += 1i64
    }
    w.ctheta = ct
    if ct > 0.0f64 {
        *xp = 0
    } else {
        *xp = 1
        ret 0.0f64
    }
    let lct = mylog(ct)
    w.ctheta = lct
    var logl = 0.0f64
    var f = 0.0f64
    i = 0i64
    while i < w.nd {
        if w.same[u(i)] == 0 {
            f = pol3(coef, u(w.idata[u(i)]) * 4usize, w.data[u(i)]) - lct
        }
        logl = logl + f
        i += 1i64
    }
    w.ctheta = myexp(0.0f64 - lct)
    if what == 0 { ret logl }
    // score and Hessian of the integral part
    i = 0i64
    while i < ndim {
        var j = 0i64
        while j < ndim {
            p.info[ii(i, j)] = 0.0f64
            j += 1i64
        }
        p.score[u(i)] = 0.0f64
        i += 1i64
    }
    var jx = 0i64
    while jx < nip - 1i64 {
        savecode1(w, p, jx)
        jx += 1i64
    }
    let nd = f64(w.nd)
    i = 0i64
    while i < ndim {
        var j = 0i64
        while j < ndim {
            p.info[ii(i, j)] = nd * p.info[ii(i, j)] * w.ctheta
            j += 1i64
        }
        p.score[u(i)] = 0.0f64 - nd * p.score[u(i)] * w.ctheta
        i += 1i64
    }
    i = 0i64
    while i < ndim {
        var j = 0i64
        while j < ndim {
            p.info[ii(i, j)] = p.info[ii(i, j)] - p.score[u(i)] * p.score[u(j)] / nd
            j += 1i64
        }
        i += 1i64
    }
    if what == 1 {
        i = 0i64
        while i < ndim {
            w.cuu[u(i)] = p.score[u(i)]
            i += 1i64
        }
    }
    i = 0i64
    while i < ndim {
        p.score[u(i)] = p.score[u(i)] + p.sumunc[u(i)]
        i += 1i64
    }
    i = 0i64
    while i < ndim {
        var j = i + 1i64
        while j < ndim {
            p.info[ii(i, j)] = p.info[ii(j, i)]
            j += 1i64
        }
        i += 1i64
    }
    ret logl
}

// --- the Rao statistic of a candidate knot

fn getnewc2(w: *S, p: *Sp, loc: f64) -> i64 {
    let t = w.tb3
    let nip = p.nip
    t[1usize] = p.knots[u(p.nk - 2i64)]
    t[2usize] = p.knots[u(p.nk - 1i64)]
    t[0usize] = loc
    var iit: [3]i64 = zero
    var j = 0usize
    while j < 3usize {
        iit[j] = nip - 1i64
        var i = 1i64
        while i < nip {
            if p.ips[u(i)] >= t[j] {
                iit[j] = i
                i = nip
            } else {
                i += 1i64
            }
        }
        j += 1usize
    }
    var c30 = iit[0] - 1i64
    if iit[1] < iit[0] - 1i64 { c30 = iit[1] }
    let c31 = nip + 1i64
    if c30 < 0i64 { c30 = 0i64 }
    w.rc3[0usize] = c30
    w.rc3[1usize] = c31
    // cc[0..2] are the combination weights; t[3..] unused
    let cw = w.tcoef
    cw[0usize] = 1.0f64
    cw[1usize] = (t[0usize] - t[2usize]) / (t[2usize] - t[1usize])
    cw[2usize] = (t[1usize] - t[0usize]) / (t[2usize] - t[1usize])
    let c2 = w.raoc2
    var r = 0i64
    while r < nip {
        var k = 0usize
        while k < 4usize {
            c2[u(r) * 4usize + k] = 0.0f64
            k += 1usize
        }
        r += 1i64
    }
    r = c30
    while r <= c31 {
        var j1 = 0usize
        while j1 < 3usize {
            if r >= iit[j1] {
                c2[u(r) * 4usize + 3usize] = c2[u(r) * 4usize + 3usize] + cw[j1]
                c2[u(r) * 4usize + 2usize] = c2[u(r) * 4usize + 2usize] - 3.0f64 * cw[j1] * t[j1]
                c2[u(r) * 4usize + 1usize] = c2[u(r) * 4usize + 1usize] + 3.0f64 * cw[j1] * t[j1] * t[j1]
                c2[u(r) * 4usize] = c2[u(r) * 4usize] - cw[j1] * t[j1] * t[j1] * t[j1]
            }
            j1 += 1usize
        }
        r += 1i64
    }
    // j0ext
    var j0ext = nip + 100i64
    if t[0usize] < p.ips[1usize] {
        j0ext = 0i64
    } else {
        var i = 1i64
        while i < nip - 2i64 {
            if t[0usize] == p.ips[u(i)] {
                j0ext = 0i64 - 1i64
            } else {
                if t[0usize] < p.ips[u(i + 1i64)] { j0ext = i }
            }
            if j0ext < nip + 50i64 {
                i = nip
            } else {
                i += 1i64
            }
        }
    }
    if j0ext > nip + 50i64 { j0ext = nip - 2i64 }
    // c2ext
    let ce = w.tc2ext
    var q = 0usize
    while q < 4usize {
        ce[q] = 0.0f64
        q += 1usize
    }
    var j1 = 0usize
    while j1 < 3usize {
        if t[j1] <= t[0usize] {
            ce[3usize] = ce[3usize] + cw[j1]
            ce[2usize] = ce[2usize] - 3.0f64 * cw[j1] * t[j1]
            ce[1usize] = ce[1usize] + 3.0f64 * cw[j1] * t[j1] * t[j1]
            ce[0usize] = ce[0usize] - cw[j1] * t[j1] * t[j1] * t[j1]
        }
        j1 += 1usize
    }
    // intext
    let coef = w.trrr
    let rrr = w.tint2ext
    if j0ext >= 0i64 {
        var jq = 0usize
        while jq < 4usize {
            coef[jq] = 0.0f64
            var k = 0i64
            while k < p.ndim {
                coef[jq] = coef[jq] + p.beta[u(k)] * p.c2[c2i(p, k, j0ext, jq)]
                k += 1i64
            }
            jq += 1usize
        }
        if j0ext == 0i64 {
            if p.ilow == 1 {
                l1int(rrr, 0usize, t[0usize], coef, 0usize, 1, 1)
            } else {
                l2int(rrr, 0usize, p.low, t[0usize], coef, 0usize, 1)
            }
        }
        if j0ext == nip - 2i64 { l2int(rrr, 0usize, p.ips[u(j0ext)], t[0usize], coef, 0usize, 1) }
        if j0ext > 0i64 && j0ext < nip - 2i64 { m1int(w, rrr, 0usize, p.ips[u(j0ext)], t[0usize], 1, coef, 0usize, 0) }
        var i = 0usize
        while i < 7usize {
            w.tintext[i] = rrr[i]
            i += 1usize
        }
    }
    // sumunc of the candidate
    var su = 0.0f64
    var m = 0i64
    while m < w.nd {
        let j0 = w.idata[u(m)]
        if j0 >= c30 && j0 <= c31 {
            if j0 != j0ext || t[0usize] > w.data[u(m)] {
                su = su + pol3(c2, u(j0) * 4usize, w.data[u(m)])
            } else {
                su = su + pol3(ce, 0usize, w.data[u(m)])
            }
        }
        m += 1i64
    }
    w.rsum = su
    ret j0ext
}

fn save22coden(w: *S, p: *Sp, czz: []f64, co: usize, j0ext: i64) -> f64 {
    let i1 = p.nip - 1i64
    var cz = 0.0f64
    let ki = w.kints
    let bc2 = w.raoc2
    if j0ext >= 0i64 && j0ext < i1 {
        var k = 0usize
        while k < 7usize {
            ki[u(j0ext) * 7usize + k] = ki[u(j0ext) * 7usize + k] - w.tint2ext[k]
            k += 1usize
        }
    }
    var j = 0i64
    while j < i1 {
        if j >= w.rc3[0usize] && j <= w.rc3[1usize] {
            var k = 0i64
            while k < p.ndim {
                if j >= p.c3[u(k) * 2usize] && j <= p.c3[u(k) * 2usize + 1usize] {
                    czz[co + u(k)] = czz[co + u(k)] + mat3(ki, u(j) * 7usize, p.c2, c2i(p, k, j, 0usize), bc2, u(j) * 4usize)
                }
                k += 1i64
            }
            cz = cz + inp3(ki, u(j) * 7usize, bc2, u(j) * 4usize)
            czz[co + u(p.ndim)] = czz[co + u(p.ndim)] + mat3(ki, u(j) * 7usize, bc2, u(j) * 4usize, bc2, u(j) * 4usize)
        }
        j += 1i64
    }
    if j0ext >= 0i64 && j0ext < i1 {
        var k = 0i64
        while k < p.ndim {
            if j0ext >= p.c3[u(k) * 2usize] && j0ext <= p.c3[u(k) * 2usize + 1usize] {
                if j0ext >= w.rc3[0usize] && j0ext <= w.rc3[1usize] {
                    czz[co + u(k)] = czz[co + u(k)] + mat3(w.tint2ext, 0usize, p.c2, c2i(p, k, j0ext, 0usize), w.tc2ext, 0usize)
                }
            }
            k += 1i64
        }
        cz = cz + inp3(w.tint2ext, 0usize, w.tc2ext, 0usize)
        czz[co + u(p.ndim)] = czz[co + u(p.ndim)] + mat3(w.tint2ext, 0usize, w.tc2ext, 0usize, w.tc2ext, 0usize)
        var q = 0usize
        while q < 7usize {
            ki[u(j0ext) * 7usize + q] = ki[u(j0ext) * 7usize + q] + w.tint2ext[q]
            q += 1usize
        }
    }
    ret cz
}

fn praox(w: *S, p: *Sp, iext: []f64, io: usize, j0ext: i64) -> f64 {
    let ndim = p.ndim
    let nd = f64(w.nd)
    if j0ext >= 0i64 {
        var i = 0usize
        while i < 7usize {
            w.tint2ext[i] = w.kints[u(j0ext) * 7usize + i] - w.tintext[i]
            i += 1usize
        }
    }
    var j = 0i64
    while j <= ndim {
        iext[io + u(j)] = 0.0f64
        j += 1i64
    }
    var sext = save22coden(w, p, iext, io, j0ext)
    j = 0i64
    while j <= ndim {
        iext[io + u(j)] = nd * iext[io + u(j)] * w.ctheta
        j += 1i64
    }
    sext = 0.0f64 - nd * sext * w.ctheta
    j = 0i64
    while j < ndim {
        iext[io + u(j)] = iext[io + u(j)] - sext * w.cuu[u(j)] / nd
        j += 1i64
    }
    iext[io + u(ndim)] = iext[io + u(ndim)] - sext * sext / nd
    sext = sext + w.rsum
    ret sext
}

fn rao(w: *S, p: *Sp, loc: f64) -> f64 {
    let ndim = p.ndim
    let m = w.raoii
    let ss = w.raoss
    var i = 0i64
    while i < ndim {
        var j = 0i64
        while j < ndim {
            m[ii(i, j)] = p.info[ii(i, j)]
            j += 1i64
        }
        ss[u(i)] = 0.0f64
        i += 1i64
    }
    let j0ext = getnewc2(w, p, loc)
    ss[u(ndim)] = praox(w, p, m, ii(ndim, 0i64), j0ext)
    i = 0i64
    while i < ndim {
        m[ii(i, ndim)] = m[ii(ndim, i)]
        i += 1i64
    }
    let r = ss[u(ndim)]
    let good = lusolve2(w, m, u(ndim) + 1usize, ss)
    ret ss[u(ndim)] * r
}

// --- searching for a knot

fn dlocation(what: i64, x: []f64, nx: i64, k: f64) -> i64 {
    if what == 1 {
        if x[0usize] > k { ret 0i64 }
        if x[u(nx - 1i64)] <= k { ret nx - 1i64 }
        var i = 0i64
        while i < nx - 1i64 {
            if x[u(i + 1i64)] > k && x[u(i)] <= k { ret i }
            i += 1i64
        }
    }
    if x[u(nx - 1i64)] < k { ret nx - 1i64 }
    if x[0usize] >= k { ret 0i64 }
    var i = 1i64
    while i < nx {
        if x[u(i)] >= k && x[u(i - 1i64)] < k { ret i }
        i += 1i64
    }
    ret nx
}

fn findyl(uu: i64, l: i64, x: []f64) -> i64 {
    if x[u(l)] == x[u(uu)] { ret 0i64 - 1i64 }
    var i = (uu + l - 1i64) / 2i64
    if x[u(i)] != x[u(uu)] { ret i }
    i = (i + l) / 2i64
    if x[u(i)] != x[u(uu)] { ret i }
    ret l
}

fn findyr(uu: i64, l: i64, x: []f64) -> i64 {
    if x[u(l)] == x[u(uu)] { ret 0i64 - 1i64 }
    var i = (uu + l + 1i64) / 2i64
    if x[u(i)] != x[u(l)] { ret i }
    i = (i + uu) / 2i64
    if x[u(i)] != x[u(l)] { ret i }
    ret uu
}

// ll and uu come back through the two-element slice lu2
fn findl(lu2: []i64, mind: i64, x: []f64, nx: i64, knt: f64) -> i64 {
    lu2[1usize] = dlocation(0, x, nx, knt)
    if lu2[1usize] < mind { ret 0i64 - 1i64 }
    var i = (lu2[1usize] - 1i64) / 2i64
    if lu2[1usize] - i < mind + 1i64 { i = lu2[1usize] - mind - 1i64 }
    lu2[0usize] = 0i64
    lu2[1usize] = lu2[1usize] - mind - 1i64
    ret i
}

fn findr(lu2: []i64, mind: i64, x: []f64, nx: i64, knt: f64) -> i64 {
    lu2[0usize] = dlocation(1, x, nx, knt)
    if nx - 1i64 - lu2[0usize] < mind { ret 0i64 - 1i64 }
    var i = (nx + lu2[0usize]) / 2i64
    if i - lu2[0usize] < mind + 1i64 { i = lu2[0usize] + mind + 1i64 }
    lu2[1usize] = nx - 1i64
    lu2[0usize] = lu2[0usize] + mind + 1i64
    ret i
}

fn findm(lu2: []i64, mind: i64, x: []f64, nx: i64, k0: f64, k1: f64) -> i64 {
    lu2[0usize] = dlocation(1, x, nx, k0)
    lu2[1usize] = dlocation(0, x, nx, k1)
    if lu2[1usize] - lu2[0usize] < 2i64 * mind + 1i64 { ret 0i64 - 1i64 }
    lu2[1usize] = lu2[1usize] - mind - 1i64
    lu2[0usize] = lu2[0usize] + mind + 1i64
    ret (lu2[1usize] + lu2[0usize]) / 2i64
}

// the new starting coefficients after adding a knot: solve one coefficient matrix against the other
fn betaadd(w: *S, p: *Sp, p2: *Sp, besti: i64) {
    let k = p.ndim + 3i64
    let t1 = w.betaaddt1
    let v1 = w.betaaddv1
    var i = 0i64
    while i < p2.nk + 2i64 {
        v1[u(i)] = 0.0f64
        var j = 0i64
        while j < p2.ndim {
            v1[u(i)] = v1[u(i)] + p2.beta[u(j)] * p2.c1[c1i(j, i)]
            j += 1i64
        }
        i += 1i64
    }
    i = p2.nk
    while i > besti {
        v1[u(i + 2i64)] = v1[u(i + 1i64)]
        i = i - 1i64
    }
    v1[u(besti + 2i64)] = 0.0f64
    i = 0i64
    while i < k {
        var j = 0i64
        while j < k {
            t1[ii(i, j)] = 0.0f64
            j += 1i64
        }
        i += 1i64
    }
    var j = 0i64
    while j < k {
        i = 0i64
        while i < k - 3i64 {
            t1[ii(i, j)] = p.c1[c1i(i, j)]
            i += 1i64
        }
        j += 1i64
    }
    i = k - 2i64
    while i < k {
        t1[ii(i, i)] = 1.0f64
        i += 1i64
    }
    t1[ii(k - 3i64, 0i64)] = 1.0f64
    luinverse(w, t1, u(k))
    i = 0i64
    while i < k - 3i64 {
        p.beta[u(i)] = 0.0f64
        j = 0i64
        while j < k {
            p.beta[u(i)] = p.beta[u(i)] + t1[ii(j, i)] * v1[u(j)]
            j += 1i64
        }
        i += 1i64
    }
}

// --- the basis

fn getonec1(c: []f64, co: usize, i: i64, t: []f64, j: i64) {
    c[co + u(i)] = 1.0f64
    c[co + u(i + 3i64)] = (t[u(j + 2i64)] - t[u(j)]) * (t[u(j)] - t[u(j + 1i64)]) / ((t[u(j + 2i64)] - t[u(j + 3i64)]) * (t[u(j + 1i64)] - t[u(j + 3i64)]))
    c[co + u(i + 2i64)] = (c[co + u(i + 3i64)] * (t[u(j + 1i64)] - t[u(j + 3i64)]) + t[u(j + 1i64)] - t[u(j)]) / (t[u(j + 2i64)] - t[u(j + 1i64)])
    c[co + u(i + 1i64)] = 0.0f64 - 1.0f64 - c[co + u(i + 3i64)] - c[co + u(i + 2i64)]
}

// the power-basis representation of basis function i (c1 row at co)
fn getc1(w: *S, t: []f64, c: []f64, co: usize, i: i64, k: i64) {
    var j = 0i64
    while j <= k + 1i64 {
        c[co + u(j)] = 0.0f64
        j += 1i64
    }
    if i == 0i64 {
        let a = t[2usize] - t[0usize]
        let b = t[2usize] - t[1usize]
        c[co + 2usize] = 1.0f64
        c[co + 3usize] = 0.0f64 - a / b
        c[co + 4usize] = 0.0f64 - c[co + 2usize] - c[co + 3usize]
        c[co + 1usize] = 0.0f64 - 3.0f64 * (t[0usize] * t[0usize] + c[co + 3usize] * t[1usize] * t[1usize] + c[co + 4usize] * t[2usize] * t[2usize])
        c[co] = 0.0f64 - t[2usize] * c[co + 1usize] - c[co + 2usize] * a * a * a - c[co + 3usize] * b * b * b
    }
    if i == 1i64 {
        c[co + u(k - 1i64)] = 1.0f64
        c[co + u(k)] = (t[u(k - 3i64)] - t[u(k - 1i64)]) / (t[u(k - 1i64)] - t[u(k - 2i64)])
        c[co + u(k + 1i64)] = 0.0f64 - c[co + u(k)] - c[co + u(k - 1i64)]
    }
    if i == 2i64 { getonec1(c, co, k - 2i64, t, k - 4i64) }
    if i > 2i64 {
        let d = w.tb3
        getonec1(c, co, i - 1i64, t, i - 3i64)
        // d is a 10-vector in C; the slots 4.. of tcoef hold it here
        let dd = w.trrr
        getonec1(dd, 0usize, 0i64, t, i - 2i64)
        var a = 0.0f64
        var b = 0.0f64
        var jj = 0i64
        while jj < 4i64 {
            var r = t[u(k - 1i64)] - t[u(i + jj - 2i64)]
            a = a + dd[u(jj)] * r * r * r
            r = t[u(k - 1i64)] - t[u(i + jj - 3i64)]
            b = b + c[co + u(i + jj - 1i64)] * r * r * r
            jj += 1i64
        }
        jj = 0i64
        while jj < 4i64 {
            c[co + u(i + jj)] = c[co + u(i + jj)] - dd[u(jj)] * b / a
            jj += 1i64
        }
    }
}

fn getc2(w: *S, p: *Sp) {
    var m = 0i64
    var i = 0i64
    while i < p.ndim {
        p.c3[u(i) * 2usize] = p.iks[u(i) * 5usize] - 1i64
        p.c3[u(i) * 2usize + 1usize] = p.iks[u(i) * 5usize + 2usize] + 1i64
        if i == 0i64 { p.c3[0usize] = 0i64 }
        if i == 1i64 || i == 2i64 { p.c3[u(i) * 2usize + 1usize] = p.nip }
        if i > 2i64 { p.c3[u(i) * 2usize + 1usize] = p.iks[u(i) * 5usize + 4usize] + 1i64 }
        var j = 0i64
        while j < p.nip {
            var k = 0usize
            while k < 4usize {
                p.c2[c2i(p, i, j, k)] = 0.0f64
                k += 1usize
            }
            j += 1i64
        }
        j = p.c3[u(i) * 2usize]
        while j <= p.c3[u(i) * 2usize + 1usize] {
            var l = 5i64
            if i == 0i64 || i == 1i64 { l = 3i64 }
            if i == 2i64 { l = 4i64 }
            if i == 0i64 {
                p.c2[c2i(p, i, j, 0usize)] = p.c2[c2i(p, i, j, 0usize)] + p.c1[c1i(i, 0i64)]
                p.c2[c2i(p, i, j, 1usize)] = p.c2[c2i(p, i, j, 1usize)] + p.c1[c1i(i, 1i64)]
            }
            var n = 0i64
            while n < l {
                if i == 0i64 { m = n }
                if i == 1i64 { m = p.nk - 3i64 + n }
                if i == 2i64 { m = p.nk - 4i64 + n }
                if i > 2i64 { m = i + n - 3i64 }
                let a = p.knots[u(m)]
                var b = p.c1[c1i(i, 2i64 + m)]
                if j >= p.iks[u(i) * 5usize + u(n)] {
                    p.c2[c2i(p, i, j, 3usize)] = p.c2[c2i(p, i, j, 3usize)] + b
                    b = a * b
                    p.c2[c2i(p, i, j, 2usize)] = p.c2[c2i(p, i, j, 2usize)] - 3.0f64 * b
                    b = a * b
                    p.c2[c2i(p, i, j, 1usize)] = p.c2[c2i(p, i, j, 1usize)] + 3.0f64 * b
                    b = a * b
                    p.c2[c2i(p, i, j, 0usize)] = p.c2[c2i(p, i, j, 0usize)] - b
                }
                n += 1i64
            }
            j += 1i64
        }
        p.sumunc[u(i)] = 0.0f64
        m = 0i64
        while m < w.nd {
            let l = w.idata[u(m)]
            if l >= p.c3[u(i) * 2usize] && l <= p.c3[u(i) * 2usize + 1usize] {
                p.sumunc[u(i)] = p.sumunc[u(i)] + pol3(p.c2, c2i(p, i, l, 0usize), w.data[u(m)])
            }
            m += 1i64
        }
        i += 1i64
    }
}

// integration points, the data's interval index, and which integration points belong to each basis function
fn getip(w: *S, p: *Sp) {
    let iips = w.getiips
    let ips = p.ips
    var nip = 1i64
    iips[0usize] = 0i64 - 4i64
    iips[1usize] = p.iknots[0usize]
    ips[0usize] = p.low
    ips[1usize] = p.knots[0usize]
    var i = 1i64
    while i < p.nk {
        var j = p.iknots[u(i)] - p.iknots[u(i - 1i64)]
        j = i64(math.floor[f64](f64(j) / 100.0f64)) + 1i64
        var k = 1i64
        while k < j {
            nip = nip + 1i64
            iips[u(nip)] = p.iknots[u(i - 1i64)] + k * (p.iknots[u(i)] - p.iknots[u(i - 1i64)]) / j
            ips[u(nip)] = w.data[u(iips[u(nip)])]
            k += 1i64
        }
        nip = nip + 1i64
        ips[u(nip)] = p.knots[u(i)]
        iips[u(nip)] = p.iknots[u(i)]
        i += 1i64
    }
    nip = nip + 1i64
    ips[u(nip)] = p.upp
    iips[u(nip)] = w.nd + 4i64
    nip = nip + 1i64
    p.nip = nip
    i = 0i64
    while i < nip - 1i64 {
        var j = iips[u(i)]
        while j <= iips[u(i + 1i64)] - 1i64 {
            if j >= 0i64 && j < w.nd { w.idata[u(j)] = i }
            j += 1i64
        }
        i += 1i64
    }
    i = 0i64
    while i < p.nk {
        let j = p.iknots[u(i)]
        iips[u(i)] = w.idata[u(j)]
        i += 1i64
    }
    i = 0i64
    while i < 3i64 {
        p.iks[u(i)] = iips[u(i)]
        i += 1i64
    }
    i = 0i64
    while i < 3i64 {
        p.iks[5usize + u(i)] = iips[u(i - 3i64 + p.nk)]
        i += 1i64
    }
    if p.ndim > 2i64 {
        i = 0i64
        while i < 4i64 {
            p.iks[10usize + u(i)] = iips[u(i - 4i64 + p.nk)]
            i += 1i64
        }
    }
    var j = 3i64
    while j < p.ndim {
        i = 0i64
        while i < 5i64 {
            p.iks[u(j) * 5usize + u(i)] = iips[u(j + i - 3i64)]
            i += 1i64
        }
        j += 1i64
    }
}

fn setupspace(w: *S, p: *Sp) {
    getip(w, p)
    var i = 0i64
    while i < p.ndim {
        getc1(w, p.knots, p.c1, c1i(i, 0i64), i, p.nk)
        i += 1i64
    }
    getc2(w, p)
}

// --- Newton-Raphson

fn iterx(w: *S, p: *Sp) -> i64 {
    let zerror = 0.000001f64
    let maxiter = 100i64
    var it = 0i64
    var logl = 0.0f64
    var lnew = 0.0f64
    var i1 = 0i64
    var i2 = 0i64
    var iq = 0i64
    while it < maxiter {
        logl = pompall(w, p, 2, &i1)
        if it == 0i64 && fabs(w.xxa) > 0.01f64 && w.xxa - logl > 100.0f64 {
            lnew = logl
            var j = 0i64
            while j < p.ndim {
                w.itertmp1[u(j)] = p.score[u(j)]
                w.itertmp2[u(j)] = p.beta[u(j)]
                p.beta[u(j)] = 0.0f64
                var i = 0i64
                while i < p.ndim {
                    w.itertmp3[ii(i, j)] = p.info[ii(i, j)]
                    i += 1i64
                }
                j += 1i64
            }
            startnow(w, p)
            logl = pompall(w, p, 2, &i2)
            if lnew > logl {
                logl = lnew
                j = 0i64
                while j < p.ndim {
                    p.score[u(j)] = w.itertmp1[u(j)]
                    p.beta[u(j)] = w.itertmp2[u(j)]
                    var i = 0i64
                    while i < p.ndim {
                        p.info[ii(i, j)] = w.itertmp3[ii(i, j)]
                        i += 1i64
                    }
                    j += 1i64
                }
            } else {
                i1 = i2
            }
        }
        if i1 == 1 { ret 7i64 }
        let good = lusolve2(w, p.info, u(p.ndim), p.score)
        if !good { ret 2i64 }
        if p.ilow == 1 {
            p.score[0usize] = 0.0f64 - p.score[0usize] / p.beta[0usize]
            if p.score[0usize] < 0.0f64 - 100.0f64 { p.score[0usize] = 0.0f64 - 100.0f64 }
        }
        if p.iupp == 1 {
            p.score[1usize] = 0.0f64 - p.score[1usize] / p.beta[1usize]
            if p.score[1usize] < 0.0f64 - 100.0f64 { p.score[1usize] = 0.0f64 - 100.0f64 }
        }
        var factor = 0.0f64 - 1.0f64
        if p.ilow == 1 && p.iupp == 1 && p.beta[0usize] == 0.0f64 && p.beta[1usize] == 0.0f64 { ret 6i64 }
        if p.ilow == 1 && p.beta[0usize] >= 0.0f64 { ret 4i64 }
        if p.iupp == 1 && p.beta[1usize] >= 0.0f64 { ret 3i64 }
        if p.ilow == 0 {
            p.beta[0usize] = p.beta[0usize] - factor * p.score[0usize]
        } else {
            p.beta[0usize] = 0.0f64 - myexp(factor * p.score[0usize] + mylog(0.0f64 - p.beta[0usize]))
        }
        if p.iupp == 0 {
            p.beta[1usize] = p.beta[1usize] - factor * p.score[1usize]
        } else {
            p.beta[1usize] = 0.0f64 - myexp(factor * p.score[1usize] + mylog(0.0f64 - p.beta[1usize]))
        }
        var j = 2i64
        while j < p.ndim {
            p.beta[u(j)] = p.beta[u(j)] - factor * p.score[u(j)]
            j += 1i64
        }
        var again = true
        while again {
            if p.ilow == 1 && p.iupp == 1 && p.beta[0usize] == 0.0f64 && p.beta[1usize] == 0.0f64 { ret 6i64 }
            if p.ilow == 1 && p.beta[0usize] >= 0.0f64 { ret 4i64 }
            if p.iupp == 1 && p.beta[1usize] >= 0.0f64 { ret 3i64 }
            lnew = pompall(w, p, 0, &iq)
            var kk = 0i64
            if lnew - logl < 0.0f64 - zerror { kk = 1i64 }
            if lnew - logl < 0.0f64 - zerror * 100.0f64 && p.ilow == 1 && p.beta[0usize] > 0.0f64 - 1.0e8f64 { kk = 1i64 }
            if lnew - logl < 0.0f64 - zerror * 100.0f64 && p.iupp == 1 && p.beta[1usize] > 0.0f64 - 1.0e8f64 { kk = 1i64 }
            if kk == 1i64 || (iq == 1 && fabs(factor) > 0.1f64) {
                iq = 0i64
                factor = factor / 2.0f64
                if p.ilow == 0 {
                    p.beta[0usize] = p.beta[0usize] + factor * p.score[0usize]
                } else {
                    p.beta[0usize] = 0.0f64 - myexp(0.0f64 - factor * p.score[0usize] + mylog(0.0f64 - p.beta[0usize]))
                }
                if p.iupp == 0 {
                    p.beta[1usize] = p.beta[1usize] + factor * p.score[1usize]
                } else {
                    p.beta[1usize] = 0.0f64 - myexp(0.0f64 - factor * p.score[1usize] + mylog(0.0f64 - p.beta[1usize]))
                }
                j = 2i64
                while j < p.ndim {
                    p.beta[u(j)] = p.beta[u(j)] + factor * p.score[u(j)]
                    j += 1i64
                }
                if fabs(factor) < 0.00001f64 && ((p.iupp == 1 && p.beta[1usize] > 0.0f64 - 1.0e8f64) || (p.ilow == 1 && p.beta[0usize] > 0.0f64 - 1.0e8f64)) { ret 5i64 }
                if fabs(factor) < 0.00001f64 { ret 8i64 }
            }
            if iq == 1i64 { ret 7i64 }
            again = kk == 1i64
        }
        if fabs(lnew - logl) < zerror && fabs(factor) > 0.96f64 { it = maxiter + 1000i64 }
        if fabs(lnew - logl) < zerror * 100.0f64 && p.ilow == 1 && p.beta[0usize] > 0.0f64 - 1.0e8f64 { it = maxiter + 1000i64 }
        if fabs(lnew - logl) < zerror * 100.0f64 && p.iupp == 1 && p.beta[1usize] > 0.0f64 - 1.0e8f64 { it = maxiter + 1000i64 }
        it = it + 1i64
    }
    if it < maxiter + 500i64 { ret 1i64 }
    logl = pompall(w, p, 1, &iq)
    w.xxa = logl
    p.aic = logl
    p.cth = w.ctheta
    ret 0i64
}

// governs the bounds: try the unbounded tail if the coefficients allow it, else widen the bounded interval
fn iter(w: *S, p: *Sp) -> i64 {
    let xpp = p.upp
    var lpp = p.upp
    var lll = p.low
    let xll = p.low
    var n = 0i64
    let mll = p.ilow
    let muu = p.iupp
    if p.ilow == 0 && p.iupp == 0 { ret iterx(w, p) }
    while n < 6i64 || n == 0i64 {
        n = n + 1i64
        if (p.beta[1usize] < 0.0f64 || muu == 0) && (p.beta[0usize] < 0.0f64 || mll == 0) {
            p.low = xll
            p.ilow = mll
            p.upp = xpp
            p.iupp = muu
            let oops = iterx(w, p)
            if oops == 0i64 || n == 6i64 { ret oops }
        }
        p.iupp = 0
        p.ilow = 0
        if muu == 1 { p.upp = 4.0f64 * lpp - 3.0f64 * p.low }
        if mll == 1 { p.low = 4.0f64 * lll - 3.0f64 * p.upp }
        lpp = p.upp
        lll = p.low
        let oops = iterx(w, p)
        p.iupp = muu
        p.upp = xpp
        p.ilow = mll
        p.low = xll
        if oops != 0i64 { ret oops }
    }
    ret 9999i64
}

// --- starting values and the starting knots

fn startnow(w: *S, p: *Sp) {
    var i = 0i64
    while i < p.ndim {
        p.beta[u(i)] = 0.0f64
        i += 1i64
    }
    let r0 = (p.knots[0usize] + p.knots[1usize]) / 2.0f64
    let r1 = (p.knots[u(p.nk - 2i64)] + p.knots[u(p.nk - 1i64)]) / 2.0f64
    var j0 = 0i64
    var j1 = 0i64
    var s0 = 0.0f64
    var s1 = 0.0f64
    i = 0i64
    while i < w.nd {
        if w.data[u(i)] < r0 {
            s0 = s0 + r0 - w.data[u(i)]
            j0 = j0 + 2i64
        }
        if w.data[u(i)] > r1 {
            s1 = s1 + w.data[u(i)] - r1
            j1 = j1 + 2i64
        }
        i += 1i64
    }
    s0 = 2.0f64 * s0 / f64(j0)
    s1 = 2.0f64 * s1 / f64(j1)
    if p.ilow == 1 { p.beta[0usize] = 0.0f64 - 1.0f64 / fabs(s0 * p.c1[c1i(0i64, 1i64)]) }
    if p.iupp == 1 { p.beta[1usize] = 0.0f64 - 1.0f64 / fabs(s1 * p.c2[c2i(p, 1i64, p.nip, 1usize)]) }
}

fn rearrange(w: *S, p: *Sp) -> bool {
    let sorted = w.rearsorted
    let ix = w.rearix
    let nk = p.nk
    var i = 0i64
    while i < w.nd {
        sorted[u(i)] = w.data[u(i)]
        ix[u(i)] = i
        i += 1i64
    }
    var k = 1i64
    i = 1i64
    while i < w.nd {
        if sorted[u(i)] > sorted[u(k - 1i64)] {
            sorted[u(k)] = sorted[u(i)]
            ix[u(k)] = ix[u(i)]
            k += 1i64
        }
        i += 1i64
    }
    var jx: [70]i64 = zero
    var isx = 0i64
    i = 0i64
    while i < nk {
        var j = isx
        while j < k {
            if p.knots[u(i)] <= sorted[u(j)] {
                jx[u(i)] = j
                isx = j
                j = k
            } else {
                j += 1i64
            }
        }
        i += 1i64
    }
    isx = 0i64
    while isx < 10i64 {
        var j = 1i64
        while j < nk - 1i64 {
            if jx[u(j)] == jx[u(j - 1i64)] {
                if jx[u(j + 1i64)] > jx[u(j)] { jx[u(j)] = jx[u(j)] + 1i64 }
            }
            j += 1i64
        }
        j = nk - 2i64
        while j > 0i64 {
            if jx[u(j)] == jx[u(j + 1i64)] {
                if jx[u(j - 1i64)] < jx[u(j)] { jx[u(j)] = jx[u(j)] - 1i64 }
            }
            j = j - 1i64
        }
        isx += 1i64
    }
    var l = 1i64
    var j = 1i64
    while j < nk {
        if jx[u(j)] == jx[u(j - 1i64)] { l = 0i64 }
        j += 1i64
    }
    if l == 0i64 { ret false }
    i = 0i64
    while i < nk {
        p.iknots[u(i)] = ix[u(jx[u(i)])]
        p.knots[u(i)] = sorted[u(jx[u(i)])]
        i += 1i64
    }
    ret true
}

fn startspace(w: *S, p: *Sp, strt: i64) -> bool {
    let k = w.nd
    var ok1 = true
    var l = 0i64
    if strt == 0i64 {
        p.iknots[0usize] = 0i64
        p.iknots[1usize] = k / 2i64
        p.iknots[2usize] = k - 1i64
        var i = 0usize
        while i < 3usize {
            p.knots[i] = w.data[u(p.iknots[i])]
            i += 1usize
        }
        p.nk = 3i64
        p.ndim = 2i64
    }
    if strt < 0i64 {
        if strt == 0i64 - 1i64 {
            l = p.nk
            let r = f64(l) + 2.0f64
            if l > 3i64 {
                let s = f64(l) / (f64(l) - 3.0f64)
                var i = 1i64
                while i < l - 1i64 {
                    p.iknots[u(i)] = i64((((f64(i - 1i64) * s + 1.0f64) / r)) * f64(k))
                    i += 1i64
                }
            } else {
                p.iknots[1usize] = i64(f64(k - 1i64) / 2.0f64)
            }
            p.iknots[0usize] = 0i64
            p.iknots[u(l - 1i64)] = k - 1i64
        }
        if strt == 0i64 - 2i64 {
            l = p.nk
            let r = f64(l) + 4.0f64
            if l > 3i64 {
                let s = f64(l + 2i64) / (f64(l) - 3.0f64)
                var i = 1i64
                while i < l - 1i64 {
                    p.iknots[u(i)] = i64((((f64(i - 1i64) * s + 1.0f64) / r)) * f64(k))
                    i += 1i64
                }
            } else {
                p.iknots[1usize] = i64(f64(k - 1i64) / 2.0f64)
            }
            p.iknots[0usize] = 1i64
            p.iknots[u(l - 1i64)] = k - 2i64
        }
        if strt == 0i64 - 3i64 {
            l = p.nk - 2i64
            let r = f64(l) + 2.0f64
            var s = 0.0f64
            if l > 3i64 { s = f64(l) / (f64(l) - 3.0f64) }
            var i = 1i64
            while i < l - 1i64 {
                p.iknots[u(i + 1i64)] = i64(((f64(i - 1i64) * s + 1.0f64) / r) * (f64(k) - 8.0f64) + 4.0f64)
                i += 1i64
            }
            p.iknots[1usize] = 4i64
            p.iknots[u(l)] = k - 5i64
            p.iknots[0usize] = 0i64
            p.iknots[u(l + 1i64)] = k - 1i64
            l = l + 2i64
        }
        var i = 0i64
        while i < l {
            p.knots[u(i)] = w.data[u(p.iknots[u(i)])]
            if i > 0i64 {
                if p.knots[u(i)] <= p.knots[u(i - 1i64)] { ok1 = false }
            }
            i += 1i64
        }
        p.nk = l
        if !ok1 { ok1 = rearrange(w, p) }
        if !ok1 { ret false }
        p.ndim = l - 1i64
    }
    if p.ilow == 1 { p.low = w.data[0usize] }
    if p.iupp == 1 { p.upp = w.data[u(k - 1i64)] }
    setupspace(w, p)
    startnow(w, p)
    ret ok1
}

// --- adding a knot

fn adddim(w: *S, p: *Sp, p2: *Sp, mind: i64) -> i64 {
    let sorted = w.data
    let nx = w.nd
    let lu2 = w.rearix
    var loloc = 0i64
    var uploc = 0i64
    var bestloc = 0i64 - 1i64
    var besti = 0i64 - 1i64
    var bestrao = 0.0f64 - 1.0f64
    var nowloc1 = 0i64
    var ll = 0i64
    var uu = 0i64
    swapspace(p2, p)
    var i = 0i64
    while i <= p.nk {
        if i == 0i64 { nowloc1 = findl(lu2, mind, sorted, nx, p.knots[0usize]) }
        if i == p.nk { nowloc1 = findr(lu2, mind, sorted, nx, p.knots[u(p.nk - 1i64)]) }
        if i > 0i64 && i < p.nk { nowloc1 = findm(lu2, mind, sorted, nx, p.knots[u(i - 1i64)], p.knots[u(i)]) }
        ll = lu2[0usize]
        uu = lu2[1usize]
        if nowloc1 >= 0i64 {
            let nowrao1 = rao(w, p, sorted[u(nowloc1)])
            if nowrao1 > bestrao {
                loloc = ll
                uploc = uu
                bestloc = nowloc1
                bestrao = nowrao1
                besti = i
            }
        }
        i += 1i64
    }
    if bestloc < 0i64 { ret 0i64 - 1i64 }
    var going = true
    while going {
        if sorted[u(uploc)] > sorted[u(loloc)] {
            let nowloc2 = findyr(uploc, bestloc, sorted)
            var nowrao2 = bestrao
            if nowloc2 >= 0i64 { nowrao2 = rao(w, p, sorted[u(nowloc2)]) }
            let nl1 = findyl(bestloc, loloc, sorted)
            var nowrao1 = bestrao
            if nl1 >= 0i64 { nowrao1 = rao(w, p, sorted[u(nl1)]) }
            if bestrao >= nowrao2 && bestrao >= nowrao1 {
                loloc = uploc
            } else {
                if nowrao1 > bestrao {
                    uploc = bestloc
                    bestloc = nl1
                    bestrao = nowrao1
                } else {
                    loloc = bestloc
                    bestloc = nowloc2
                    bestrao = nowrao2
                }
            }
        }
        going = sorted[u(uploc)] > sorted[u(loloc)]
    }
    if bestloc < 0i64 { ret bestloc }
    if besti == p.nk {
        p.knots[u(p.nk)] = sorted[u(bestloc)]
        p.iknots[u(p.nk)] = bestloc
    } else {
        i = p.nk
        while i > besti {
            p.knots[u(i)] = p.knots[u(i - 1i64)]
            p.iknots[u(i)] = p.iknots[u(i - 1i64)]
            i = i - 1i64
        }
        p.knots[u(besti)] = sorted[u(bestloc)]
        p.iknots[u(besti)] = bestloc
    }
    p.nk = p.nk + 1i64
    p.ndim = p.ndim + 1i64
    setupspace(w, p)
    betaadd(w, p, p2, besti)
    ret 1i64
}

// --- removing a knot

fn redo1(p: *Sp, irmax: i64, k: i64) {
    var i0 = 0i64
    var i1 = 2i64
    let i2 = 3i64
    if irmax == 2i64 { i1 = 1i64 }
    if irmax == 0i64 { i0 = 1i64 }
    let t = p.knots
    var i = 0i64
    while i <= k + 1i64 {
        p.c1[c1i(0i64, i)] = 0.0f64
        i += 1i64
    }
    let a = t[u(i2)] - t[u(i0)]
    let b = t[u(i2)] - t[u(i1)]
    p.c1[c1i(0i64, i0 + 2i64)] = 1.0f64
    p.c1[c1i(0i64, i1 + 2i64)] = 0.0f64 - a / b
    p.c1[c1i(0i64, i2 + 2i64)] = 0.0f64 - 1.0f64 - p.c1[c1i(0i64, i1 + 2i64)]
    let c1v = p.c1[c1i(0i64, i1 + 2i64)]
    let c2v = p.c1[c1i(0i64, i2 + 2i64)]
    p.c1[c1i(0i64, 1i64)] = 0.0f64 - 3.0f64 * (t[u(i0)] * t[u(i0)] + c1v * t[u(i1)] * t[u(i1)] + c2v * t[u(i2)] * t[u(i2)])
    p.c1[c1i(0i64, 0i64)] = 0.0f64 - t[u(i2)] * p.c1[c1i(0i64, 1i64)] - p.c1[c1i(0i64, i0 + 2i64)] * a * a * a - c1v * b * b * b
}

fn redo2(p: *Sp, irmax: i64, k: i64) {
    let i0 = k - 4i64
    var i1 = k - 3i64
    var i2 = k - 1i64
    if irmax == k - 3i64 { i1 = k - 2i64 }
    if irmax == k - 1i64 { i2 = k - 2i64 }
    let t = p.knots
    var i = 0i64
    while i <= k + 1i64 {
        p.c1[c1i(1i64, i)] = 0.0f64
        i += 1i64
    }
    p.c1[c1i(1i64, i0 + 2i64)] = 1.0f64
    p.c1[c1i(1i64, i1 + 2i64)] = (t[u(i0)] - t[u(i2)]) / (t[u(i2)] - t[u(i1)])
    p.c1[c1i(1i64, i2 + 2i64)] = 0.0f64 - 1.0f64 - p.c1[c1i(1i64, i1 + 2i64)]
}

// Inv(H) A' Inv(A Inv(H) A') A, then beta shifted; mm2 is j by i (stride MK5), the new coefficients end in r1
fn solver(w: *S, mm2: []f64, i: i64, j: i64, r1: []f64, p: *Sp) {
    let c1 = w.solc1
    let c2 = w.solc2
    let c3 = w.solc3
    if i == j {
        var k0 = 0i64
        while k0 < i {
            r1[u(k0)] = 0.0f64
            k0 += 1i64
        }
    }
    var k0 = 0i64
    while k0 < i {
        var k1 = 0i64
        while k1 < j {
            c1[ii(k0, k1)] = 0.0f64
            var k2 = 0i64
            while k2 < i {
                c1[ii(k0, k1)] = c1[ii(k0, k1)] + p.info[ii(k0, k2)] * mm2[ii(k1, k2)]
                k2 += 1i64
            }
            k1 += 1i64
        }
        k0 += 1i64
    }
    k0 = 0i64
    while k0 < j {
        var k1 = 0i64
        while k1 < j {
            c2[ii(k0, k1)] = 0.0f64
            var k2 = 0i64
            while k2 < i {
                c2[ii(k0, k1)] = c2[ii(k0, k1)] + mm2[ii(k0, k2)] * c1[ii(k2, k1)]
                k2 += 1i64
            }
            k1 += 1i64
        }
        k0 += 1i64
    }
    luinverse(w, c2, u(j))
    k0 = 0i64
    while k0 < i {
        var k1 = 0i64
        while k1 < j {
            c3[ii(k0, k1)] = 0.0f64
            var k2 = 0i64
            while k2 < j {
                c3[ii(k0, k1)] = c3[ii(k0, k1)] + c1[ii(k0, k2)] * c2[ii(k2, k1)]
                k2 += 1i64
            }
            k1 += 1i64
        }
        k0 += 1i64
    }
    k0 = 0i64
    while k0 < i {
        var k1 = 0i64
        while k1 < i {
            c1[ii(k0, k1)] = 0.0f64
            var k2 = 0i64
            while k2 < j {
                c1[ii(k0, k1)] = c1[ii(k0, k1)] + c3[ii(k0, k2)] * mm2[ii(k2, k1)]
                k2 += 1i64
            }
            k1 += 1i64
        }
        k0 += 1i64
    }
    k0 = 0i64
    while k0 < i {
        r1[u(k0)] = p.beta[u(k0)]
        var k1 = 0i64
        while k1 < i {
            r1[u(k0)] = r1[u(k0)] - c1[ii(k0, k1)] * p.beta[u(k1)]
            k1 += 1i64
        }
        k0 += 1i64
    }
}

// r1[i] = sum_j beta_j c1[j][i] for the nk + 2 power-basis coefficients of model p
fn topower(p: *Sp, r1: []f64) {
    var i = 0i64
    while i < p.nk + 2i64 {
        r1[u(i)] = 0.0f64
        var j = 0i64
        while j < p.ndim {
            r1[u(i)] = r1[u(i)] + p.beta[u(j)] * p.c1[c1i(j, i)]
            j += 1i64
        }
        i += 1i64
    }
}

// solve for the beta of model dst (k functions) that reproduce the power coefficients r1, using c1 of src
fn refit(w: *S, src: *Sp, dst: *Sp, k: i64, r1: []f64) {
    let mm2 = w.betaremm2
    var i = 0i64
    while i < k + 3i64 {
        var j = 0i64
        while j < k + 3i64 {
            mm2[ii(i, j)] = 0.0f64
            j += 1i64
        }
        i += 1i64
    }
    var j = 0i64
    while j < k + 3i64 {
        i = 0i64
        while i < k {
            mm2[ii(i, j)] = src.c1[c1i(i, j)]
            i += 1i64
        }
        j += 1i64
    }
    i = k + 1i64
    while i < k + 3i64 {
        mm2[ii(i, i)] = 1.0f64
        i += 1i64
    }
    mm2[ii(k, 0i64)] = 1.0f64
    luinverse(w, mm2, u(k + 3i64))
    i = 0i64
    while i < k {
        dst.beta[u(i)] = 0.0f64
        j = 0i64
        while j < k + 3i64 {
            dst.beta[u(i)] = dst.beta[u(i)] + mm2[ii(j, i)] * r1[u(j)]
            j += 1i64
        }
        i += 1i64
    }
}

fn betarem(w: *S, p2: *Sp, p: *Sp, irmax: i64) {
    var k = p2.ndim
    let mm2 = w.betaremm2
    let r1 = w.betaremr1
    var i = 0i64
    while i < k {
        mm2[ii(0i64, i)] = p2.c1[c1i(i, irmax + 2i64)]
        i += 1i64
    }
    solver(w, mm2, k, 1i64, r1, p2)
    if (p.ilow == 1 && r1[0usize] >= 0.0f64) || (p.iupp == 1 && r1[1usize] >= 0.0f64) {
        if p.ilow == 1 && p.iupp == 0 {
            if irmax <= 2i64 {
                topower(p2, r1)
                redo1(p2, irmax, k)
                refit(w, p2, p2, k, r1)
            }
            i = 0i64
            while i < k {
                mm2[ii(0i64, i)] = p2.c1[c1i(i, irmax + 2i64)]
                mm2[ii(1i64, i)] = 0.0f64
                i += 1i64
            }
            mm2[ii(1i64, 0i64)] = 1.0f64
            let x = p2.beta[0usize]
            p2.beta[0usize] = 0.0f64
            solver(w, mm2, k, 2i64, r1, p2)
            r1[0usize] = r1[0usize] + x
        }
        if p.ilow == 0 && p.iupp == 1 {
            if irmax >= k - 2i64 {
                topower(p2, r1)
                redo2(p2, irmax, p2.nk)
                refit(w, p2, p2, k, r1)
                topower(p2, r1)
            }
            i = 0i64
            while i < k {
                mm2[ii(0i64, i)] = p2.c1[c1i(i, irmax + 2i64)]
                mm2[ii(1i64, i)] = 0.0f64
                i += 1i64
            }
            mm2[ii(1i64, 1i64)] = 1.0f64
            let x = p2.beta[1usize]
            p2.beta[1usize] = 0.0f64
            solver(w, mm2, k, 2i64, r1, p2)
            r1[1usize] = r1[1usize] + x
        }
        if p.ilow == 1 && p.iupp == 1 {
            if irmax > k - 3i64 || irmax <= 2i64 {
                topower(p2, r1)
                if irmax <= 2i64 { redo1(p2, irmax, k) }
                if irmax > k - 3i64 { redo2(p2, irmax, p2.nk) }
                refit(w, p2, p2, k, r1)
            }
            i = 0i64
            while i < k {
                mm2[ii(0i64, i)] = p2.c1[c1i(i, irmax + 2i64)]
                mm2[ii(1i64, i)] = 0.0f64
                mm2[ii(2i64, i)] = 0.0f64
                i += 1i64
            }
            mm2[ii(1i64, 0i64)] = 1.0f64
            mm2[ii(2i64, 1i64)] = 1.0f64
            let x = p2.beta[0usize]
            p2.beta[0usize] = 0.0f64
            let y = p2.beta[1usize]
            p2.beta[1usize] = 0.0f64
            solver(w, mm2, k, 3i64, r1, p2)
            r1[0usize] = r1[0usize] + x
            r1[1usize] = r1[1usize] + y
        }
    }
    i = 0i64
    while i < p2.ndim {
        p2.beta[u(i)] = r1[u(i)]
        i += 1i64
    }
    topower(p2, r1)
    i = irmax
    while i < p2.nk {
        r1[u(i + 2i64)] = r1[u(i + 3i64)]
        i += 1i64
    }
    k = k - 1i64
    refit(w, p, p, k, r1)
}

fn remdim(w: *S, p: *Sp, p2: *Sp) {
    let ndim = p.ndim
    var ratmax = 0.0f64
    var irmax = 1i64
    luinverse(w, p.info, u(ndim))
    swapspace(p2, p)
    var i = 0i64
    while i < p.nk {
        var phi = 0.0f64
        var j = 0i64
        while j < ndim {
            phi = phi + p.beta[u(j)] * p.c1[c1i(j, i + 2i64)]
            j += 1i64
        }
        phi = fabs(phi)
        var se = 0.0f64
        j = 0i64
        while j < ndim {
            var k = 0i64
            while k < ndim {
                se = se - p.c1[c1i(j, i + 2i64)] * p.c1[c1i(k, i + 2i64)] * p.info[ii(j, k)]
                k += 1i64
            }
            j += 1i64
        }
        se = math.sqrt[f64](fabs(se))
        if se > phi * ratmax {
            ratmax = se / phi
            irmax = i
        }
        i += 1i64
    }
    p.nk = p.nk - 1i64
    p.ndim = p.ndim - 1i64
    i = irmax
    while i < p.nk {
        p.iknots[u(i)] = p.iknots[u(i + 1i64)]
        p.knots[u(i)] = p.knots[u(i + 1i64)]
        i += 1i64
    }
    setupspace(w, p)
    betarem(w, p2, p, irmax)
}

// --- the starting knots when none are given

fn five00(w: *S, k: i64, n: i64) {
    let rr = w.fiverr
    let fi = 4.0f64
    let nf = f64(n)
    let j = i64(math.floor[f64]((f64(k) - 1.0f64) / 2.0f64 + 0.99f64))
    let j2 = i64(math.floor[f64]((f64(k) - 1.0f64) / 2.0f64))
    var eps1 = fi - math.pow[f64]((nf - 1.0f64) / fi, 1.0f64 / (f64(j) - 1.0f64))
    if eps1 > 0.0f64 { eps1 = 0.0f64 }
    var eps2 = fi - 1.0f64
    var i = 0i64
    while i < k {
        rr[u(i)] = 0.0f64
        i += 1i64
    }
    rr[0usize] = 1.0f64
    rr[u(k)] = nf
    var i1 = 0i64
    while i1 < 100i64 {
        if i1 == 0i64 || eps2 - eps1 > 0.0001f64 {
            let eps = (eps1 + eps2) / 2.0f64
            var s = 1.0f64
            var wv = fi
            i = 1i64
            while i <= j2 {
                var v = f64(i)
                s = s + wv
                rr[u(i)] = s
                rr[u(k - i - 1i64)] = nf + 1.0f64 - s
                v = fi - v * eps
                if v < 1.0f64 { v = 1.0f64 }
                wv = wv * v
                i += 1i64
            }
            if 2i64 * j == k {
                s = s + wv / 2.0f64
            } else {
                rr[u(j)] = (nf + 1.0f64) / 2.0f64
            }
            if 2.0f64 * s >= nf + 1.0f64 {
                eps1 = eps
            } else {
                eps2 = eps
            }
            i1 += 1i64
        } else {
            i1 = 100i64
        }
    }
    i = 0i64
    while i < k {
        rr[u(i)] = (rr[u(i)] - 1.0f64) / (nf - 1.0f64)
        i += 1i64
    }
}

fn five01(w: *S, k: i64, n: i64, il: i64) {
    let rr = w.fiverr
    five00(w, 2i64 * k - 1i64, 2i64 * n)
    var i = 0i64
    while i < k {
        rr[u(i)] = 2.0f64 * rr[u(i)]
        i += 1i64
    }
    if il == 0i64 {
        i = 0i64
        while i < k {
            rr[u(i)] = 1.0f64 - rr[u(2i64 * k - 2i64 - i)]
            i += 1i64
        }
    }
}

fn five(w: *S, kts: []f64, k: i64, ilowf: i64, iuppf: i64) {
    let n1 = w.nd
    let rr = w.fiverr
    if ilowf + iuppf == 2i64 { five00(w, k, n1) }
    if ilowf + iuppf == 1i64 { five01(w, k, n1, iuppf) }
    if ilowf + iuppf == 0i64 {
        var i = 0i64
        while i < k {
            rr[u(i)] = f64(i) / f64(k - 1i64)
            i += 1i64
        }
    }
    let ee = w.fiveee
    let h1 = w.fiveh1
    ee[0usize] = 1.0f64
    h1[0usize] = 0.0f64
    h1[1usize] = 1.0f64
    var l = 0i64
    var i = 1i64
    while i < n1 {
        if w.same[u(i)] == 1 {
            h1[u(l + 1i64)] = h1[u(l + 1i64)] + 1.0f64
        } else {
            l = l + 1i64
            ee[u(l)] = w.data[u(i)]
            h1[u(l + 1i64)] = h1[u(l)] + 1.0f64
        }
        i += 1i64
    }
    i = 0i64
    while i < l {
        h1[u(i)] = 0.5f64 * (h1[u(i)] + h1[u(i + 1i64)])
        i += 1i64
    }
    let h2 = h1[0usize]
    var h3 = 0.0f64
    i = 0i64
    while i < l {
        h1[u(i)] = h1[u(i)] - h2
        if h1[u(i)] > h3 { h3 = h1[u(i)] }
        i += 1i64
    }
    i = 0i64
    while i < l {
        h1[u(i)] = h1[u(i)] / h3
        i += 1i64
    }
    kts[0usize] = w.data[0usize]
    kts[u(k - 1i64)] = w.data[u(n1 - 1i64)]
    i = 1i64
    while i < k - 1i64 {
        var g1 = 0i64
        var g2 = l
        var j = 0i64
        while j < l {
            if h1[u(j)] <= rr[u(i)] && j > g1 { g1 = j }
            if h1[u(j)] > rr[u(i)] && j < g2 { g2 = j }
            j += 1i64
        }
        let ha = h1[u(g1)]
        let hb = h1[u(g2)]
        let hc = (rr[u(i)] - ha) / (hb - ha)
        kts[u(i)] = hc * ee[u(g2)] + (1.0f64 - hc) * ee[u(g1)]
        i += 1i64
    }
}

// --- the search

fn nlsd(w: *S, best: *Sp, cur: *Sp, trynew: *Sp, alpha: f64, ndmax0: i64, mind: i64, strt: i64, logs: []f64, ad: []i64) -> i64 {
    var add = 1i64
    var oops = 0i64
    var oops2 = 0i64
    var oops3 = 0i64
    var coco = 0i64
    var ndmax = ndmax0
    swapspace(cur, best)
    if !startspace(w, cur, strt) { ret 39i64 }
    let ndm2 = ndmax
    if ndmax < 0i64 { ndmax = 0i64 - ndmax }
    best.aic = math.pow[f64](10.0f64, 150.0f64)
    var i = 0i64
    while i < MK {
        logs[u(i)] = 0.0f64 - math.pow[f64](10.0f64, 150.0f64)
        i += 1i64
    }
    var go = true
    while go {
        if oops3 == 0i64 { oops = iter(w, cur) }
        if (oops > 0i64 || oops3 > 0i64) && ndmax > cur.ndim {
            var redo = true
            while redo {
                i = 0i64 - 1i64
                while i > 0i64 - 4i64 {
                    w.xxa = 0.0f64
                    coco = coco + 1i64
                    if !startspace(w, cur, i) { ret 39i64 }
                    if coco == 10i64 { ret 39i64 }
                    oops = iter(w, cur)
                    oops2 = oops2 + 1i64
                    if oops == 0i64 { i = 0i64 - 10i64 }
                    i = i - 1i64
                }
                redo = oops != 0i64 && ndmax > cur.ndim
            }
        }
        if oops2 > 2i64 { oops2 = oops2 - 1i64 }
        if oops != 0i64 {
            if best.aic < 0.0f64 - 1.0e149f64 { ret 40i64 }
            swapspace(cur, best)
            add = 0i64
        }
        if oops == 0i64 {
            logs[u(cur.ndim - 1i64)] = cur.aic
            ad[u(cur.ndim - 1i64)] = 1
            cur.aic = f64(cur.ndim) * alpha - 2.0f64 * cur.aic
            if cur.ndim == ndmax { add = 0 }
            if cur.aic < best.aic { swapspace(best, cur) }
        }
        if add == 1i64 && ndm2 < 0i64 {
            i = 2i64
            while i < cur.ndim - 2i64 {
                if logs[u(cur.ndim - 1i64)] - logs[u(i - 1i64)] < f64(cur.ndim - i) / 2.0f64 - 0.5f64 {
                    add = 0i64
                    ndmax = cur.ndim
                }
                i += 1i64
            }
        }
        if add == 1i64 {
            add = adddim(w, cur, trynew, mind)
            if add != 1i64 && oops2 < 2i64 { ndmax = cur.ndim }
            if add != 1i64 && oops2 >= 2i64 {
                oops3 = 1i64
                add = 1i64
            }
        }
        go = add == 1i64
    }
    if cur.ndim > 2i64 {
        var more = true
        while more {
            if ndmax > 2i64 { remdim(w, cur, trynew) }
            oops = iter(w, cur)
            if oops != 0i64 {
                oops = oops + 100i64
                best.ndim = ndmax - 1i64
                ret oops
            }
            if cur.aic > logs[u(cur.ndim - 1i64)] {
                logs[u(cur.ndim - 1i64)] = cur.aic
                ad[u(cur.ndim - 1i64)] = 2
            }
            cur.aic = f64(cur.ndim) * alpha - 2.0f64 * cur.aic
            if cur.aic < best.aic { swapspace(best, cur) }
            more = cur.aic - best.aic < alpha * f64(cur.ndim - 2i64)
        }
    }
    best.ndim = ndmax - 1i64
    if oops2 > 0i64 { ret 100i64 }
    ret 0i64
}

type LsFit = struct {
    code: i64, nknots: usize, ndim: i64, coef: []f64, knots: []f64, logl: []f64, ad: []i64, penalty: f64, mind: i64
}

// logspline() on sorted data x (length >= 10). maxknots 0 means the default; nknots_arg is R's -nknots (or the number of
// user knots, with the knots in kts_in); penalty < 0 means log(n); mind < 1 means the default. lower and upper say a bound exists.
fn logspline_fit(a: *mem.Arena, x: []const f64, maxknots: i64, nknots_arg: i64, lower: bool, lbound: f64, upper: bool, ubound: f64, penalty: f64, mind0: i64, kts_in: []const f64) -> (LsFit, err) {
    var fit: LsFit = zero
    let n = x.len
    let (w0, ew) = makes(a, x, n)
    if ew != ok { ret (fit, ew) }
    var w = w0
    // sameness of neighbouring observations
    w.same[0usize] = 0
    var i = 1usize
    while i < n {
        if x[i] == x[i - 1usize] {
            w.same[i] = 1
        } else {
            if x[i] != 0.0f64 {
                let r = fabs(x[i - 1usize] / x[i] - 1.0f64)
                if r < 0.0000000000001f64 {
                    w.same[i] = 1
                } else {
                    w.same[i] = 0
                }
            } else {
                w.same[i] = 0
            }
        }
        i += 1usize
    }
    let (best, e1) = newsp(a, w.kk)
    let (cur, e2) = newsp(a, w.kk)
    let (trynew, e3) = newsp(a, w.kk)
    let (kts, e4) = zf(a, MK5 + 5usize)
    let (logs, e5) = zf(a, MK5 + 5usize)
    let (ad, e6) = zi(a, MK5 + 5usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (fit, mem.Full) }
    var bs = best
    var cs = cur
    var ts = trynew
    let nd = i64(n)
    var mind = mind0
    if mind < 1i64 {
        mind = i64(2.5f64 * math.pow[f64](f64(nd), 0.2f64) + 0.5f64)
        if nd / mind < 10i64 { mind = nd / 10i64 }
        if mind < 3i64 { mind = 3i64 }
    }
    var strt = nknots_arg
    var ndmax = maxknots
    var alpha = penalty
    if alpha < 0.0f64 { alpha = mylog(f64(nd)) }
    var ilowf = 1i64
    var iuppf = 1i64
    bs.ilow = 1
    bs.iupp = 1
    if lower {
        ilowf = 0i64
        bs.ilow = 0
        bs.low = lbound
    }
    if upper {
        iuppf = 0i64
        bs.iupp = 0
        bs.upp = ubound
    }
    if ndmax == 0i64 { ndmax = 0i64 - i64(math.floor[f64](4.0f64 * math.pow[f64](f64(nd), 0.2f64) + 1.0f64)) }
    if ndmax > MK { ndmax = MK }
    var user = false
    if strt > 0i64 && kts_in.len > 0usize { user = true }
    if user {
        i = 0usize
        while i < kts_in.len {
            kts[i] = kts_in[i]
            i += 1usize
        }
    }
    if strt <= 0i64 {
        if strt < 0i64 {
            strt = 0i64 - strt
        } else {
            strt = i64(math.floor[f64](2.5f64 * math.pow[f64](f64(nd), 0.2f64) + 1.0f64))
        }
        if strt < 3i64 { strt = 3i64 }
        five(&w, kts, strt, ilowf, iuppf)
    }
    if ndmax > 0i64 && strt > ndmax + 1i64 { strt = i64(math.floor[f64](f64(ndmax + 3i64) / 2.0f64)) }
    if ndmax < 0i64 && strt > 0i64 - ndmax { strt = i64(math.floor[f64](f64(3i64 - ndmax) / 2.0f64)) }
    // the starting knots are in kts
    bs.nk = strt
    bs.ndim = strt - 1i64
    i = 0usize
    while i < usize(strt) {
        bs.knots[i] = kts[i]
        i += 1usize
    }
    var j = 0i64
    var y = 0.0f64 - math.pow[f64](10.0f64, 100.0f64)
    i = 0usize
    var scanning = true
    while scanning && i < n {
        let xv = w.data[i]
        if y <= bs.knots[u(j)] && xv > bs.knots[u(j)] {
            bs.iknots[u(j)] = i64(i)
            j += 1i64
            if j == bs.nk {
                scanning = false
            }
        } else {
            y = xv
            i += 1usize
        }
    }
    if j == bs.nk - 1i64 { bs.iknots[u(bs.nk - 1i64)] = nd - 1i64 }
    if j < bs.nk - 1i64 {
        fit.code = 17
        ret (fit, ok)
    }
    if bs.iknots[1usize] == 0i64 {
        fit.code = 18
        ret (fit, ok)
    }
    w.cuu[0usize] = 0.0f64
    let code = nlsd(&w, &bs, &cs, &ts, alpha, ndmax, mind, 1i64, logs, ad)
    fit.code = code
    fit.penalty = alpha
    fit.mind = mind
    if code > 0i64 && code < 100i64 { ret (fit, ok) }
    fit.nknots = usize(bs.nk)
    fit.ndim = bs.ndim
    let (coef, e7) = zf(a, usize(bs.nk) + 2usize)
    let (kn, e8) = zf(a, usize(bs.nk) + 1usize)
    if e7 != ok || e8 != ok { ret (fit, mem.Full) }
    i = 0usize
    while i < usize(bs.nk) + 2usize {
        coef[i] = 0.0f64
        j = 0i64
        while j < bs.nk - 1i64 {
            coef[i] = coef[i] + bs.beta[u(j)] * bs.c1[c1i(j, i64(i))]
            j += 1i64
        }
        i += 1usize
    }
    coef[0usize] = coef[0usize] + mylog(bs.cth)
    i = 0usize
    while i < usize(bs.nk) {
        kn[i] = bs.knots[i]
        i += 1usize
    }
    fit.coef = coef
    fit.knots = kn
    fit.logl = logs
    fit.ad = ad
    ret (fit, ok)
}
