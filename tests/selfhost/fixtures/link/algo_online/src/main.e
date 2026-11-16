use e.algo.online as online
use e.io
use e.math
use e.mem

error Failed

fn lcg(s: u64) -> u64 { ret (s * 1103515245u64 + 12345u64) % 2147483648u64 }

fn ski_checks() -> err {
    let buy = 10.0f64
    var days = 1.0f64
    while days <= 60.0f64 {
        let opt = online.ski_offline(days, buy)
        if online.ski_break_even(days, buy) > 2.0f64 * opt { ret Failed }
        var lam = 0.25f64
        while lam <= 1.0f64 {
            // a correct prediction: consistent with the true length
            let good = online.ski_predicted(days, buy, days, lam)
            if good > (1.0f64 + lam) * opt + 1.0f64 { ret Failed }
            // an arbitrary prediction: robust to (1 + 1/lambda) of the optimum
            let bad1 = online.ski_predicted(days, buy, 0.0f64, lam)
            let bad2 = online.ski_predicted(days, buy, 1000.0f64, lam)
            if bad1 > (1.0f64 + 1.0f64 / lam) * opt + 1.0f64 { ret Failed }
            if bad2 > (1.0f64 + 1.0f64 / lam) * opt + 1.0f64 { ret Failed }
            lam += 0.25f64
        }
        days += 1.0f64
    }
    ret ok
}

fn paging_checks(seed0: u64) -> err {
    var seed = seed0
    var reqs: [60]usize = zero
    var i = 0usize
    while i < 60usize {
        seed = lcg(seed)
        reqs[i] = usize((seed >> 12u64) % 6u64)
        i += 1usize
    }
    let k = 3usize
    var cache: [3]usize = zero
    var stamp: [3]usize = zero
    var mark: [3]bool = zero
    let opt = online.belady(reqs[..], k, cache[..])
    let l = online.lru(reqs[..], k, cache[..], stamp[..])
    let m = online.marking(reqs[..], k, cache[..], mark[..])
    if l < opt || m < opt { ret Failed }
    if l > k * opt || m > k * opt { ret Failed }
    ret ok
}

fn mtf_checks(seed0: u64) -> err {
    var seed = seed0
    var reqs: [80]usize = zero
    var i = 0usize
    while i < 80usize {
        seed = lcg(seed)
        // skewed requests
        let r = (seed >> 12u64) % 100u64
        var item = 0usize
        if r > 50u64 { item = 1usize }
        if r > 75u64 { item = 2usize }
        if r > 88u64 { item = 3usize }
        if r > 95u64 { item = 4usize }
        reqs[i] = item
        i += 1usize
    }
    var list: [5]usize = zero
    var counts: [5]usize = zero
    let mtf = online.move_to_front(reqs[..], 5usize, list[..])
    let opt = online.static_optimal(reqs[..], 5usize, counts[..])
    if mtf > 2usize * opt { ret Failed }
    ret ok
}

fn facility_checks(seed0: u64) -> err {
    var seed = seed0
    var xs: [8]f64 = zero
    var i = 0usize
    while i < 8usize {
        seed = lcg(seed)
        xs[i] = f64((seed >> 12u64) % 1000u64) / 100.0f64
        i += 1usize
    }
    let f = 4.0f64
    var open: [8]f64 = zero
    var count: usize = 0usize
    let online_cost = online.facility_location(xs[..], f, open[..], &count)
    // brute-force optimum over the subsets of the clients' own positions
    var best = 1.0e300f64
    var mask = 1usize
    while mask < 256usize {
        var cost = 0.0f64
        i = 0usize
        while i < 8usize {
            if (mask >> i) & 1usize == 1usize { cost += f }
            i += 1usize
        }
        var c = 0usize
        while c < 8usize {
            var dn = 1.0e300f64
            i = 0usize
            while i < 8usize {
                if (mask >> i) & 1usize == 1usize {
                    let d = math.abs[f64](xs[i] - xs[c])
                    if d < dn { dn = d }
                }
                i += 1usize
            }
            cost += dn
            c += 1usize
        }
        if cost < best { best = cost }
        mask += 1usize
    }
    if online_cost < best - 1.0e-9f64 { ret Failed }
    if online_cost > 6.0f64 * best { ret Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sk = ski_checks()
    if sk != ok { ret sk }
    var s = 1u64
    while s <= 60u64 {
        let p = paging_checks(s * 7919u64)
        if p != ok { ret p }
        let m = mtf_checks(s * 104729u64)
        if m != ok { ret m }
        let f = facility_checks(s * 1299709u64)
        if f != ok { ret f }
        s += 1u64
    }
    ret ok
}
