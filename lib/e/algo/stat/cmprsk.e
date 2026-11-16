// R cmprsk::cuminc for one group and one cause: Gray's `cinc` routine, the estimate of the cumulative incidence
// function of a cause with its variance, written as the corner points of the step function (x, f, v), line for line.
//
// Not here: the k-sample test of Gray (crstm), crr (Fine-Gray regression), predict.crr and timepoints.

use e.mem

// y ascending; ic 1 when the case failed from any cause; icc 1 when from the cause of interest; x, f, v need
// 2 * (distinct cause times) + 2 slots (2 n + 2 is always enough); answers the number of points written
fn cinc(y: []const f64, ic: []const i64, icc: []const i64, x: []f64, f: []f64, v: []f64) -> usize {
    let n = y.len
    var fk = 1.0f64
    var v1 = 0.0f64
    var v2 = 0.0f64
    var v3 = 0.0f64
    // slot k of the Fortran arrays is index k - 1 here
    x[0usize] = 0.0f64
    f[0usize] = 0.0f64
    v[0usize] = 0.0f64
    var lcnt = 1usize
    var l = 1usize
    var ll = 1usize
    var rs = f64(n)
    var ty = y[0usize]
    while true {
        // find the end l of the block of tied times starting at ll
        l = ll
        while l + 1usize <= n && y[l] == ty { l += 1usize }
        var nd1 = 0.0f64
        var nd2 = 0.0f64
        var i = ll
        while i <= l {
            nd1 += f64(icc[i - 1usize])
            nd2 += f64(ic[i - 1usize] - icc[i - 1usize])
            i += 1usize
        }
        let nd = nd1 + nd2
        if nd != 0.0f64 {
            let fkn = fk * (rs - nd) / rs
            if nd1 > 0.0f64 {
                lcnt += 2usize
                f[lcnt - 2usize] = f[lcnt - 3usize]
                f[lcnt - 1usize] = f[lcnt - 2usize] + fk * nd1 / rs
            }
            if nd2 > 0.0f64 && fkn > 0.0f64 {
                var t5 = 1.0f64
                if nd2 > 1.0f64 { t5 = 1.0f64 - (nd2 - 1.0f64) / (rs - 1.0f64) }
                let t6 = fk * fk * t5 * nd2 / (rs * rs)
                let t3 = 1.0f64 / fkn
                let t4 = f[lcnt - 1usize] / fkn
                v1 += t4 * t4 * t6
                v2 += t3 * t4 * t6
                v3 += t3 * t3 * t6
            }
            if nd1 > 0.0f64 {
                var t5 = 1.0f64
                if nd1 > 1.0f64 { t5 = 1.0f64 - (nd1 - 1.0f64) / (rs - 1.0f64) }
                let t6 = fk * fk * t5 * nd1 / (rs * rs)
                var t3 = 0.0f64
                if fkn > 0.0f64 { t3 = 1.0f64 / fkn }
                let t4 = 1.0f64 + t3 * f[lcnt - 1usize]
                v1 += t4 * t4 * t6
                v2 += t3 * t4 * t6
                v3 += t3 * t3 * t6
                let t2 = f[lcnt - 1usize]
                x[lcnt - 2usize] = y[l - 1usize]
                x[lcnt - 1usize] = y[l - 1usize]
                v[lcnt - 2usize] = v[lcnt - 3usize]
                v[lcnt - 1usize] = v1 + t2 * t2 * v3 - 2.0f64 * t2 * v2
            }
            fk = fkn
        }
        rs = f64(n - l)
        l += 1usize
        if l > n { break }
        ll = l
        ty = y[l - 1usize]
    }
    lcnt += 1usize
    x[lcnt - 1usize] = y[n - 1usize]
    f[lcnt - 1usize] = f[lcnt - 2usize]
    v[lcnt - 1usize] = v[lcnt - 2usize]
    ret lcnt
}
