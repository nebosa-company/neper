// R ipred: the Brier score of survival predictions at one time (sbrier with numeric predictions) and kfoldcv.
//
// Not here: bagging, errorest, ipredknn, inbagg, slda and the out-of-bag machinery; survfit-object predictions (the predicted survival probabilities are given as numbers).

use e.mem

// the Kaplan-Meier estimate of the censoring survival (censorings as the events) at time t, right-continuous, for the observations sorted by time
fn cens_surv(time: []const f64, cens: []const f64, t: f64) -> f64 {
    let n = time.len
    var s = 1.0f64
    var j = 0usize
    while j < n && time[j] <= t {
        // one factor per distinct time: the censorings d of those at risk, where prodlim's reverse fit has tied events leave the risk set first
        var d = 0usize
        var k1 = 0usize
        var e = j
        while e < n && time[e] == time[j] {
            if cens[e] == 0.0f64 { d += 1usize } else { k1 += 1usize }
            e += 1usize
        }
        if d > 0usize { s = s * (1.0f64 - f64(d) / f64(n - j - k1)) }
        j = e
    }
    ret s
}

// sbrier for one time: pred[i] the predicted survival probability at btime of observation i (any order, as time and cens), the observations sorted internally by time
fn sbrier_one(a: *mem.Arena, time0: []const f64, cens0: []const f64, pred0: []const f64, btime: f64) -> f64 {
    let n = time0.len
    let (ord, e1) = mem.alloc[usize](a, n)
    let (time, e2) = mem.alloc[f64](a, n)
    let (cens, e3) = mem.alloc[f64](a, n)
    let (pred, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = ord[i]
        var j = i
        while j > 0usize && time0[ord[j - 1usize]] > time0[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    i = 0usize
    while i < n {
        time[i] = time0[ord[i]]
        cens[i] = cens0[ord[i]]
        pred[i] = pred0[ord[i]]
        i += 1usize
    }
    var cs = cens_surv(time, cens, btime)
    if cs == 0.0f64 { cs = 1.0f64 / 0.0f64 }
    var s = 0.0f64
    i = 0usize
    while i < n {
        var csi = cens_surv(time, cens, time[i])
        if csi == 0.0f64 { csi = 1.0f64 / 0.0f64 }
        var h1 = 0.0f64
        var h2 = 0.0f64
        if time[i] <= btime && cens[i] == 1.0f64 { h1 = 1.0f64 }
        if time[i] > btime { h2 = 1.0f64 }
        s += (0.0f64 - pred[i]) * (0.0f64 - pred[i]) * h1 * (1.0f64 / csi) + (1.0f64 - pred[i]) * (1.0f64 - pred[i]) * h2 * (1.0f64 / cs)
        i += 1usize
    }
    ret s / f64(n)
}

// kfoldcv(k, N): the k fold sizes of N observations
fn kfoldcv(k: usize, n: usize, out: []usize) {
    var i = 0usize
    if k > n {
        while i < k {
            if i < n { out[i] = 1usize } else { out[i] = 0usize }
            i += 1usize
        }
        ret
    }
    let fl = n / k
    let r = n % k
    i = 0usize
    while i < k {
        if i < r { out[i] = fl + 1usize } else { out[i] = fl }
        i += 1usize
    }
}
