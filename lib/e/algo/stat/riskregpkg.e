// R riskRegression Score() for right-censored data at one horizon: the inverse-probability-of-censoring weighted Brier score and AUC of a predicted risk, the weights from the Kaplan-Meier estimate of the censoring distribution (G at the event time from the left, G at the horizon for subjects still at risk). Times without ties.
//
// Not here: conditional censoring models, several horizons and competing risks, standard errors and confidence intervals, model comparison, calibration, net benefit.
 
use e.mem

// out[0] = Brier(horizon), out[1] = AUC(horizon)
fn score(a: *mem.Arena, t: []const f64, d: []const f64, risk: []const f64, horizon: f64, out: []f64) -> err {
    let n = t.len
    let (ord, e1) = mem.alloc[usize](a, n)
    let (gm, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var j = i
        while j > 0usize && t[ord[j - 1usize]] > t[v] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = v
        i += 1usize
    }
    // Kaplan-Meier of the censoring times: G just before each time (gm) and at the horizon
    var g = 1.0f64
    var gh = 1.0f64
    var seen_h = false
    i = 0usize
    while i < n {
        let who = ord[i]
        if !seen_h && t[who] > horizon {
            gh = g
            seen_h = true
        }
        gm[who] = g
        if d[who] < 0.5f64 { g = g * (1.0f64 - 1.0f64 / f64(n - i)) }
        i += 1usize
    }
    if !seen_h { gh = g }
    var br = 0.0f64
    i = 0usize
    while i < n {
        if t[i] <= horizon && d[i] > 0.5f64 {
            br += (1.0f64 - risk[i]) * (1.0f64 - risk[i]) / gm[i]
        }
        if t[i] > horizon { br += risk[i] * risk[i] / gh }
        i += 1usize
    }
    out[0usize] = br / f64(n)
    var num = 0.0f64
    var den = 0.0f64
    i = 0usize
    while i < n {
        if t[i] <= horizon && d[i] > 0.5f64 {
            var j = 0usize
            while j < n {
                if t[j] > horizon {
                    let w = 1.0f64 / gm[i] / gh
                    den += w
                    if risk[i] > risk[j] { num += w } else if risk[i] == risk[j] { num += 0.5f64 * w }
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    out[1usize] = num / den
    ret ok
}
