// The subset search that earth's pruning pass runs through the leaps Fortran (Alan Miller's AS274 as copied into earth): the Gentleman QR update INCLUD,
// MAKEQR, TOLSET, SSLEAPS, INITR, REPORT and VMOVE, then BAKWRD (backward elimination, DROP1), FORWRD (forward selection, ADD1), XHAUST (exhaustive search
// by branch and bound, EXADD1) and SEQREP (sequential replacement); nbest is 1 and the intercept (column 1) is forced in. Arrays are one-based as in the
// Fortran, so element 0 of each slice is unused and the transcription stays line for line.
//
// Not here: linearly dependent columns (SING; earth removes them before pruning), nbest above 1, weights.

use e.math
use e.mem

type Leaps = struct {
    np: usize,
    nrbar: usize,
    d: []f64,
    rbar: []f64,
    thetab: []f64,
    sserr: f64,
    tol: []f64,
    rss: []f64,
    vorder: []usize,
    bound: []f64,
    ress: []f64,
    lopt: []usize,
    nvmax: usize,
    first: usize,
    last: usize,
    ss: []f64,
    sxx: []f64,
    sxy: []f64,
    iwk: []usize,
}

fn lp_includ(np: usize, xrow: []f64, yel: f64, d: []f64, rbar: []f64, thetab: []f64, sserr: *f64) {
    var w = 1.0f64
    var y = yel
    var nextr = 1usize
    var i = 1usize
    while i <= np {
        if w == 0.0f64 { ret }
        let xi = xrow[i]
        if xi == 0.0f64 {
            nextr = nextr + np - i
            i += 1usize
            continue
        }
        let di = d[i]
        let wxi = w * xi
        let dpi = di + wxi * xi
        let cbar = di / dpi
        let sbar = wxi / dpi
        w = cbar * w
        d[i] = dpi
        if i != np {
            var k = i + 1usize
            while k <= np {
                let xk = xrow[k]
                xrow[k] = xk - xi * rbar[nextr]
                rbar[nextr] = cbar * rbar[nextr] + sbar * xk
                nextr += 1usize
                k += 1usize
            }
        }
        let xk2 = y
        y = xk2 - xi * thetab[i]
        thetab[i] = cbar * thetab[i] + sbar * xk2
        i += 1usize
    }
    *sserr = *sserr + w * y * y
}

fn lp_tolset(np: usize, d: []const f64, rbar: []const f64, tol: []f64) {
    var col = 1usize
    while col <= np {
        var pos = col - 1usize
        var sum = math.sqrt[f64](d[col])
        var r2 = 1usize
        while r2 + 1usize <= col {
            sum = sum + math.abs[f64](rbar[pos]) * math.sqrt[f64](d[r2])
            pos = pos + np - r2 - 1usize
            r2 += 1usize
        }
        tol[col] = 5.0e-10f64 * sum
        col += 1usize
    }
}

fn lp_ssleaps(np: usize, d: []const f64, thetab: []const f64, sserr: f64, rss: []f64) {
    var sum = sserr
    rss[np] = sserr
    var i = np
    while i >= 2usize {
        sum = sum + d[i] * (thetab[i] * thetab[i])
        rss[i - 1usize] = sum
        i -= 1usize
    }
}

// REPORT for nbest = 1: model of the first pos entries of vorder with residual sum of squares ssq replaces the best of that size when it is smaller
// and not the same subset within 0.01 percent
fn lp_report(s: *Leaps, pos: usize, ssq: f64, vorder: []const usize) {
    if pos > s.nvmax { ret }
    if ssq >= s.bound[pos] { ret }
    let l0 = pos * (pos - 1usize) / 2usize
    if ssq > 0.9999f64 * s.ress[pos] {
        var j = 1usize
        var differs = false
        while j <= pos && !differs {
            let listj = vorder[j]
            var found = false
            var i = 1usize
            while i <= pos {
                if listj == s.lopt[l0 + i] { found = true }
                i += 1usize
            }
            if !found { differs = true }
            j += 1usize
        }
        if !differs { ret }
    }
    s.ress[pos] = ssq
    var k = 1usize
    while k <= pos {
        s.lopt[l0 + k] = vorder[k]
        k += 1usize
    }
    s.bound[pos] = s.ress[pos]
}

fn lp_vmove(np: usize, vorder: []usize, d: []f64, rbar: []f64, thetab: []f64, rss: []f64, from: usize, to: usize, tol: []f64) {
    if from == to { ret }
    var first = from
    var last = to - 1usize
    var up = true
    if from > to {
        first = from - 1usize
        last = to
        up = false
    }
    var m = first
    while true {
        var m1 = (m - 1usize) * (np + np - m) / 2usize + 1usize
        var m2 = m1 + np - m
        let mp1 = m + 1usize
        var d1 = 0.0f64
        var d2 = 0.0f64
        if m <= np {
            d1 = d[m]
            if mp1 <= np { d2 = d[mp1] }
        }
        var skip = false
        if d1 == 0.0f64 && d2 == 0.0f64 { skip = true }
        if !skip {
            var x = rbar[m1]
            if math.abs[f64](x) * math.sqrt[f64](d1) < tol[mp1] { x = 0.0f64 }
            if d1 == 0.0f64 || x == 0.0f64 {
                d[m] = d2
                d[mp1] = d1
                rbar[m1] = 0.0f64
                var col = m + 2usize
                while col <= np {
                    m1 += 1usize
                    let t = rbar[m1]
                    rbar[m1] = rbar[m2]
                    rbar[m2] = t
                    m2 += 1usize
                    col += 1usize
                }
                let t2 = thetab[m]
                thetab[m] = thetab[mp1]
                thetab[mp1] = t2
            } else if d2 == 0.0f64 {
                d[m] = d1 * (x * x)
                rbar[m1] = 1.0f64 / x
                var col = m + 2usize
                while col <= np {
                    m1 += 1usize
                    rbar[m1] = rbar[m1] / x
                    col += 1usize
                }
                thetab[m] = thetab[m] / x
            } else {
                let d1new = d2 + d1 * (x * x)
                let cbar = d2 / d1new
                let sbar = x * d1 / d1new
                let d2new = d1 * cbar
                d[m] = d1new
                d[mp1] = d2new
                rbar[m1] = sbar
                var col = m + 2usize
                while col <= np {
                    m1 += 1usize
                    let y = rbar[m1]
                    rbar[m1] = cbar * rbar[m2] + sbar * y
                    rbar[m2] = y - x * rbar[m2]
                    m2 += 1usize
                    col += 1usize
                }
                let y2 = thetab[m]
                thetab[m] = cbar * thetab[mp1] + sbar * y2
                thetab[mp1] = y2 - x * thetab[mp1]
            }
        }
        if m != 1usize {
            var pos = m
            var row = 1usize
            while row + 1usize <= m {
                let x2 = rbar[pos]
                rbar[pos] = rbar[pos - 1usize]
                rbar[pos - 1usize] = x2
                pos = pos + np - row - 1usize
                row += 1usize
            }
        }
        let vm = vorder[m]
        vorder[m] = vorder[mp1]
        vorder[mp1] = vm
        let tt = tol[m]
        tol[m] = tol[mp1]
        tol[mp1] = tt
        rss[m] = rss[mp1] + d[mp1] * (thetab[mp1] * thetab[mp1])
        if up {
            m += 1usize
            if m > last { break }
        } else {
            if m == last { break }
            m -= 1usize
        }
    }
}

// DROP1: the variable among positions first..last whose removal costs the least; returns (smin, jmin)
fn lp_drop1(s: *Leaps, last: usize) -> (f64, usize) {
    let np = s.np
    let first = s.first
    var jmin = 0usize
    var smin = 1.0e35f64
    var pos1 = (first - 1usize) * (np + np - first) / 2usize + 1usize
    let inc = np - last
    var j = first
    while j <= last {
        let d1start = s.d[j]
        if math.sqrt[f64](d1start) < s.tol[j] {
            s.ss[j] = 0.0f64
            smin = 0.0f64
            jmin = j
        } else {
            var d1 = d1start
            var rhs = s.thetab[j]
            if j != last {
                var pos = pos1
                var i = j + 1usize
                while i <= last {
                    s.sxx[i] = s.rbar[pos]
                    pos += 1usize
                    i += 1usize
                }
                pos = pos + inc
                var row = j + 1usize
                while row <= last {
                    let x = s.sxx[row]
                    let d2 = s.d[row]
                    if math.abs[f64](x) * math.sqrt[f64](d1) < s.tol[row] || d2 == 0.0f64 {
                        pos = pos + np - row
                    } else {
                        d1 = d1 * d2 / (d2 + d1 * (x * x))
                        var col = row + 1usize
                        while col <= last {
                            s.sxx[col] = s.sxx[col] - x * s.rbar[pos]
                            pos += 1usize
                            col += 1usize
                        }
                        rhs = rhs - x * s.thetab[row]
                        pos = pos + inc
                    }
                    row += 1usize
                }
            }
            s.ss[j] = rhs * d1 * rhs
            if s.ss[j] < smin {
                jmin = j
                smin = s.ss[j]
            }
        }
        if j < last { pos1 = pos1 + np - j }
        j += 1usize
    }
    ret (smin, jmin)
}

// BAKWRD
fn lp_backward(s: *Leaps) {
    var pos = s.last
    while pos >= s.first + 1usize {
        let (smin, jmin) = lp_drop1(s, pos)
        let _u = smin
        if jmin > 0usize && jmin < pos {
            lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, jmin, pos, s.tol)
            var i = jmin
            while i + 1usize <= pos {
                lp_report(s, i, s.rss[i], s.vorder)
                i += 1usize
            }
        }
        pos -= 1usize
    }
}

// ADD1: the variable among positions first..last that most reduces the residual sum of squares when put at position first; (smax, jmax)
fn lp_add1(s: *Leaps, first: usize, last: usize) -> (f64, usize) {
    let np = s.np
    var j = first
    while j <= last {
        s.sxx[j] = 0.0f64
        s.sxy[j] = 0.0f64
        j += 1usize
    }
    let inc = np - last
    var pos = (first - 1usize) * (np + np - first) / 2usize + 1usize
    var row = first
    while row <= last {
        let diag = s.d[row]
        let dy = diag * s.thetab[row]
        s.sxx[row] = s.sxx[row] + diag
        s.sxy[row] = s.sxy[row] + dy
        var col = row + 1usize
        while col <= last {
            s.sxx[col] = s.sxx[col] + diag * (s.rbar[pos] * s.rbar[pos])
            s.sxy[col] = s.sxy[col] + dy * s.rbar[pos]
            pos += 1usize
            col += 1usize
        }
        pos = pos + inc
        row += 1usize
    }
    var smax = 0.0f64
    var jmax = 0usize
    j = first
    while j <= last {
        let ssqx = s.sxx[j]
        if math.sqrt[f64](ssqx) > s.tol[j] {
            s.ss[j] = (s.sxy[j] * s.sxy[j]) / s.sxx[j]
            if s.ss[j] > smax {
                smax = s.ss[j]
                jmax = j
            }
        } else {
            s.ss[j] = 0.0f64
        }
        j += 1usize
    }
    ret (smax, jmax)
}

// EXADD1 for nbest = 1
fn lp_exadd1(s: *Leaps, ivar: usize, smax: f64, jmax: usize, last: usize) {
    if jmax == 0usize { ret }
    if ivar == 0usize { ret }
    if ivar > s.nvmax { ret }
    let ltemp = s.vorder[ivar]
    var ssbase = 0.0f64
    if ivar > 1usize { ssbase = s.rss[ivar - 1usize] }
    if ivar == 1usize { ssbase = s.rss[ivar] + s.ss[1usize] }
    let temp = ssbase - smax
    if temp < s.bound[ivar] {
        s.vorder[ivar] = s.vorder[jmax]
        if jmax == ivar { s.vorder[ivar] = ltemp }
        lp_report(s, ivar, temp, s.vorder)
    }
    s.vorder[ivar] = ltemp
    let _l = last
}

// FORWRD
fn lp_forward(s: *Leaps) {
    var pos = s.first
    while pos + 1usize <= s.last {
        let (smax, jmax) = lp_add1(s, pos, s.last)
        lp_exadd1(s, pos, smax, jmax, s.last)
        if jmax > pos {
            lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, jmax, pos, s.tol)
        }
        pos += 1usize
    }
}

// SEQREP
fn lp_seqrep(s: *Leaps) {
    var nv = s.nvmax
    if s.last - 1usize < nv { nv = s.last - 1usize }
    var size = s.first
    while size <= nv {
        var count = 0i64
        var start = s.first
        while true {
            var ssred = 0.0f64
            var best = 0usize
            var from = 0usize
            var i = start
            while i <= size {
                let (smax, jmax) = lp_add1(s, size, s.last)
                if jmax > size {
                    lp_exadd1(s, size, smax, jmax, s.last)
                    if smax > ssred {
                        ssred = smax
                        best = jmax
                        if i < size {
                            from = size + start - i - 1usize
                        } else {
                            from = size
                        }
                    }
                }
                if i < size {
                    lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, size, start, s.tol)
                }
                i += 1usize
            }
            if best > size {
                if from < size {
                    lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, from, size, s.tol)
                }
                lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, best, s.first, s.tol)
                count = 0i64
                start = s.first + 1usize
            } else {
                count += 1i64
            }
            if !(count <= i64(size) - i64(start)) { break }
        }
        size += 1usize
    }
}

// XHAUST; false when a diagonal element is below its tolerance (earth then falls back to backward elimination)
fn lp_exhaustive(s: *Leaps) -> bool {
    let first = s.first
    let nvmax = s.nvmax
    var row = first
    while row <= nvmax {
        if s.d[row] <= s.tol[row] { ret false }
        lp_report(s, row, s.rss[row], s.vorder)
        row += 1usize
    }
    var i = first
    while i <= nvmax {
        s.iwk[i] = s.last
        i += 1usize
    }
    // phase 30: add1 and exadd1 at the last position; phase 40: advance the pointer
    var phase = 30usize
    var ipt = 0usize
    while true {
        if phase == 30usize {
            let lastv = s.iwk[nvmax]
            let (smax, jmax) = lp_add1(s, nvmax, lastv)
            lp_exadd1(s, nvmax, smax, jmax, lastv)
            ipt = nvmax - 1usize
            phase = 40usize
        }
        // label 40
        var advanced = false
        while !advanced {
            if ipt >= s.iwk[ipt] {
                ipt -= 1usize
                if ipt >= first { continue }
                ret true
            }
            advanced = true
        }
        let newpos = s.iwk[ipt]
        lp_vmove(s.np, s.vorder, s.d, s.rbar, s.thetab, s.rss, ipt, newpos, s.tol)
        var lim = nvmax
        if newpos - 1usize < lim { lim = newpos - 1usize }
        i = ipt
        while i <= lim {
            lp_report(s, i, s.rss[i], s.vorder)
            i += 1usize
        }
        i = ipt
        while i <= nvmax {
            s.iwk[i] = newpos - 1usize
            i += 1usize
        }
        let temp = s.rss[newpos - 1usize]
        var hit = 0usize
        i = ipt
        while i <= nvmax && hit == 0usize {
            if temp > s.bound[i] { hit = i }
            i += 1usize
        }
        if hit == 0usize {
            if s.iwk[nvmax] > nvmax {
                phase = 30usize
            } else {
                ipt = nvmax - 1usize
                phase = 40usize
            }
        } else {
            ipt = hit - 1usize
            if ipt < first { ret true }
            phase = 40usize
        }
    }
    ret true
}

// The pruning search: bx is n by np column major (column 1 the intercept), y the response; method 0 backward, 1 forward, 2 exhaustive, 3 seqrep.
// ress[k] (k = 1..nvmax) answers the best residual sum of squares of size k and lopt[k * (k - 1) / 2 + 1 .. + k] its columns in leaps order.
type Subsets = struct { np: usize, nvmax: usize, ress: []f64, lopt: []usize, good: bool }

fn leaps_search(a: *mem.Arena, bx: []const f64, y: []const f64, n: usize, np: usize, nvmax_in: usize, method: usize) -> (Subsets, err) {
    var out: Subsets = zero
    var s: Leaps = zero
    var nvmax = nvmax_in
    if np < nvmax { nvmax = np }
    let nrbar = np * (np - 1usize) / 2usize
    let (d, e1) = mem.alloc[f64](a, np + 2usize)
    let (rbar, e2) = mem.alloc[f64](a, nrbar + 2usize)
    let (thetab, e3) = mem.alloc[f64](a, np + 2usize)
    let (tol, e4) = mem.alloc[f64](a, np + 2usize)
    let (rss, e5) = mem.alloc[f64](a, np + 2usize)
    let (vorder, e6) = mem.alloc[usize](a, np + 2usize)
    let (bound, e7) = mem.alloc[f64](a, nvmax + 2usize)
    let (ress, e8) = mem.alloc[f64](a, nvmax + 2usize)
    let (lopt, e9) = mem.alloc[usize](a, nvmax * (nvmax + 1usize) / 2usize + 2usize)
    let (ss, e10) = mem.alloc[f64](a, np + 2usize)
    let (sxx, e11) = mem.alloc[f64](a, np + 2usize)
    let (sxy, e12) = mem.alloc[f64](a, np + 2usize)
    let (iwk, e13) = mem.alloc[usize](a, np + 2usize)
    let (xrow, e14) = mem.alloc[f64](a, np + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Exhausted) }
    if e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret (out, mem.Exhausted) }
    var z = 0usize
    while z < np + 2usize {
        d[z] = 0.0f64
        thetab[z] = 0.0f64
        tol[z] = 0.0f64
        rss[z] = 0.0f64
        vorder[z] = z
        ss[z] = 0.0f64
        sxx[z] = 0.0f64
        sxy[z] = 0.0f64
        iwk[z] = 0usize
        z += 1usize
    }
    z = 0usize
    while z < nrbar + 2usize {
        rbar[z] = 0.0f64
        z += 1usize
    }
    var sserr = 0.0f64
    var i = 0usize
    while i < n {
        var j = 1usize
        while j <= np {
            xrow[j] = bx[i + (j - 1usize) * n]
            j += 1usize
        }
        lp_includ(np, xrow, y[i], d, rbar, thetab, &sserr)
        i += 1usize
    }
    lp_tolset(np, d, rbar, tol)
    lp_ssleaps(np, d, thetab, sserr, rss)
    // INITR
    var nv = 1usize
    var pos = 1usize
    while nv <= nvmax {
        ress[nv] = rss[nv]
        bound[nv] = ress[nv]
        var k = 1usize
        while k <= nv {
            lopt[pos] = k
            pos += 1usize
            k += 1usize
        }
        nv += 1usize
    }
    s.np = np
    s.nrbar = nrbar
    s.d = d
    s.rbar = rbar
    s.thetab = thetab
    s.sserr = sserr
    s.tol = tol
    s.rss = rss
    s.vorder = vorder
    s.bound = bound
    s.ress = ress
    s.lopt = lopt
    s.nvmax = nvmax
    s.first = 2usize
    s.last = np
    s.ss = ss
    s.sxx = sxx
    s.sxy = sxy
    s.iwk = iwk
    var good = true
    if method == 0usize { lp_backward(&s) }
    if method == 1usize { lp_forward(&s) }
    if method == 3usize { lp_seqrep(&s) }
    if method == 2usize { good = lp_exhaustive(&s) }
    out.np = np
    out.nvmax = nvmax
    out.ress = ress
    out.lopt = lopt
    out.good = good
    ret (out, ok)
}
