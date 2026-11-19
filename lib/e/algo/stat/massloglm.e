// R MASS loglm over stats::loglin: the reduction of the formula terms to the generating margins (loglm1.default), iterative proportional fitting (AS 51 as in
// loglin.c: the deviation of each margin is measured before it is adjusted, a cycle's maximum is tested against eps), the Pearson and likelihood-ratio statistics,
// the degrees of freedom and the parameter estimates.
//
// dims[v] is the number of levels of variable v (v = 0 .. nvar - 1); a term is the bit set of its variables; the table and the fit are column-major over the dims.

use e.math
use e.mem

error BadInput

type Loglm = struct { lrt: f64, pearson: f64, df: f64, nmarg: usize, margins: []u64, fit: []f64, param: []f64, nparam: usize, nlast: usize }

fn popc(v: u64) -> usize {
    var c = 0usize
    var x = v
    while x != 0u64 {
        c += usize(x & 1u64)
        x = x >> 1u64
    }
    ret c
}

// the marginal cell of every table cell for the variables in mask: out[cell], and the number of margin cells
fn margin_index(dims: []const usize, mask: u64, out: []usize) -> usize {
    var total = 1usize
    var cells = 1usize
    var v = 0usize
    while v < dims.len {
        cells *= dims[v]
        v += 1usize
    }
    var cell = 0usize
    while cell < cells {
        var rem = cell
        var stride = 1usize
        var idx = 0usize
        v = 0usize
        while v < dims.len {
            let c = rem % dims[v]
            rem = rem / dims[v]
            if ((mask >> u64(v)) & 1u64) != 0u64 {
                idx += c * stride
                stride *= dims[v]
            }
            v += 1usize
        }
        out[cell] = idx
        cell += 1usize
    }
    v = 0usize
    while v < dims.len {
        if ((mask >> u64(v)) & 1u64) != 0u64 { total *= dims[v] }
        v += 1usize
    }
    ret total
}

fn loglm(a: *mem.Arena, dims: []const usize, tmask: []const u64, table: []const f64, start: []const f64, eps: f64, iter: usize, want_param: bool) -> (Loglm, err) {
    var out: Loglm = zero
    let nvar = dims.len
    let nt = tmask.len
    var ntab = 1usize
    var v = 0usize
    while v < nvar {
        ntab *= dims[v]
        v += 1usize
    }
    // terms ordered by degree (stable), then the generating margins
    let (ord, e0) = mem.alloc[u64](a, nt + 1usize)
    if e0 != ok { ret (out, e0) }
    var i = 0usize
    while i < nt {
        ord[i] = tmask[i]
        i += 1usize
    }
    i = 1usize
    while i < nt {
        let t = ord[i]
        var j = i
        while j > 0usize && popc(ord[j - 1usize]) > popc(t) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = t
        i += 1usize
    }
    let (mg, e1) = mem.alloc[u64](a, nt + 1usize)
    if e1 != ok { ret (out, e1) }
    var nm = 0usize
    i = 0usize
    while i < nt {
        var keep = true
        if i + 1usize < nt {
            var mx = 0usize
            var k = i + 1usize
            while k < nt {
                let ov = popc(ord[i] & ord[k])
                if ov > mx { mx = ov }
                k += 1usize
            }
            keep = popc(ord[i]) > mx
        }
        if keep {
            mg[nm] = ord[i]
            nm += 1usize
        }
        i += 1usize
    }
    // observed margins and cell maps
    let (cellmap, e2) = mem.alloc[usize](a, nm * ntab + 1usize)
    let (msize, e3) = mem.alloc[usize](a, nm + 1usize)
    let (moff, e4) = mem.alloc[usize](a, nm + 1usize)
    if e2 != ok || e3 != ok || e4 != ok { ret (out, mem.Full) }
    var tot = 0usize
    i = 0usize
    while i < nm {
        msize[i] = margin_index(dims, mg[i], cellmap[i * ntab..(i + 1usize) * ntab])
        moff[i] = tot
        tot += msize[i]
        i += 1usize
    }
    let (obs, e5) = mem.alloc[f64](a, tot + 1usize)
    let (cur, e6) = mem.alloc[f64](a, tot + 1usize)
    let (fit, e7) = mem.alloc[f64](a, ntab)
    if e5 != ok || e6 != ok || e7 != ok { ret (out, mem.Full) }
    i = 0usize
    while i < tot {
        obs[i] = 0.0f64
        i += 1usize
    }
    var cell = 0usize
    while cell < ntab {
        fit[cell] = start[cell]
        i = 0usize
        while i < nm {
            obs[moff[i] + cellmap[i * ntab + cell]] += table[cell]
            i += 1usize
        }
        cell += 1usize
    }
    var nlast = 0usize
    var cycle = 0usize
    while cycle < iter {
        cycle += 1usize
        var xmax = 0.0f64
        i = 0usize
        while i < nm {
            var j = 0usize
            while j < msize[i] {
                cur[moff[i] + j] = 0.0f64
                j += 1usize
            }
            cell = 0usize
            while cell < ntab {
                cur[moff[i] + cellmap[i * ntab + cell]] += fit[cell]
                cell += 1usize
            }
            j = 0usize
            while j < msize[i] {
                let d = math.abs[f64](obs[moff[i] + j] - cur[moff[i] + j])
                if d > xmax { xmax = d }
                j += 1usize
            }
            cell = 0usize
            while cell < ntab {
                let y = cur[moff[i] + cellmap[i * ntab + cell]]
                if y <= 0.0f64 { fit[cell] = 0.0f64 }
                if y > 0.0f64 { fit[cell] = fit[cell] * obs[moff[i] + cellmap[i * ntab + cell]] / y }
                cell += 1usize
            }
            i += 1usize
        }
        nlast = cycle
        if xmax < eps { break }
    }
    // statistics
    var pearson = 0.0f64
    var lrt = 0.0f64
    var nzero = 0usize
    cell = 0usize
    while cell < ntab {
        if start[cell] > 0.0f64 {
            let d = table[cell] - fit[cell]
            pearson += d * d / fit[cell]
        } else { nzero += 1usize }
        if table[cell] * fit[cell] > 0.0f64 { lrt += table[cell] * math.log[f64](table[cell] / fit[cell]) }
        cell += 1usize
    }
    lrt = 2.0f64 * lrt
    // degrees of freedom: every subset of every margin
    let nsub = 1usize << nvar
    let (dfv, e8) = mem.alloc[f64](a, nsub + 1usize)
    if e8 != ok { ret (out, e8) }
    i = 0usize
    while i < nsub {
        dfv[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nm {
        var s = mg[i]
        while s > 0u64 {
            var pr = 1.0f64
            v = 0usize
            while v < nvar {
                if ((s >> u64(v)) & 1u64) != 0u64 { pr = pr * f64(dims[v] - 1usize) }
                v += 1usize
            }
            dfv[usize(s) - 1usize] = pr
            s = (s - 1u64) & mg[i]
        }
        i += 1usize
    }
    var sdf = 0.0f64
    i = 0usize
    while i < nsub {
        sdf += dfv[i]
        i += 1usize
    }
    let df = f64(ntab) - sdf - 1.0f64 - f64(nzero)
    // the parameters
    var param: []f64 = fit[0usize..0usize]
    var np = 0usize
    if want_param {
        let (lf, e9) = mem.alloc[f64](a, ntab)
        var plen = 2usize
        v = 0usize
        while v < nvar {
            plen *= dims[v] + 1usize
            v += 1usize
        }
        let (pv, e10) = mem.alloc[f64](a, plen)
        if e9 != ok || e10 != ok { ret (out, mem.Full) }
        var mean = 0.0f64
        cell = 0usize
        while cell < ntab {
            lf[cell] = math.log[f64](fit[cell])
            mean += lf[cell]
            cell += 1usize
        }
        mean = mean / f64(ntab)
        pv[0usize] = mean
        np = 1usize
        cell = 0usize
        while cell < ntab {
            lf[cell] -= mean
            cell += 1usize
        }
        // terms with df > 0 in ascending index, stably ordered by size
        let (tl, e11) = mem.alloc[u64](a, nsub + 1usize)
        if e11 != ok { ret (out, e11) }
        var nterms = 0usize
        i = 1usize
        while i < nsub {
            if dfv[i - 1usize] > 0.0f64 {
                tl[nterms] = u64(i)
                nterms += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < nterms {
            let t = tl[i]
            var j = i
            while j > 0usize && popc(tl[j - 1usize]) > popc(t) {
                tl[j] = tl[j - 1usize]
                j -= 1usize
            }
            tl[j] = t
            i += 1usize
        }
        let (map, e12) = mem.alloc[usize](a, ntab)
        let (sums, e13) = mem.alloc[f64](a, ntab)
        if e12 != ok || e13 != ok { ret (out, mem.Full) }
        i = 0usize
        while i < nterms {
            let sz = margin_index(dims, tl[i], map)
            var j = 0usize
            while j < sz {
                sums[j] = 0.0f64
                j += 1usize
            }
            cell = 0usize
            while cell < ntab {
                sums[map[cell]] += lf[cell]
                cell += 1usize
            }
            let cnt = f64(ntab / sz)
            j = 0usize
            while j < sz {
                sums[j] = sums[j] / cnt
                pv[np + j] = sums[j]
                j += 1usize
            }
            cell = 0usize
            while cell < ntab {
                lf[cell] -= sums[map[cell]]
                cell += 1usize
            }
            np += sz
            i += 1usize
        }
        param = pv[0usize..np]
    }
    out = Loglm { lrt: lrt, pearson: pearson, df: df, nmarg: nm, margins: mg[0usize..nm], fit: fit, param: param, nparam: np, nlast: nlast }
    ret (out, ok)
}
