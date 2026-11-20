// R QCA superSubset(): the conjunctions of conditions (and, for necessity, the disjunctions) whose inclusion and coverage reach the cut-offs, found as C_superSubset does:
// conditions k at a time, the levels of each combination, a conjunction (or, for sufficiency, only a conjunction) that is a superset of one found with fewer conditions skipped,
// a disjunction that contains one found with fewer conditions skipped, and the search stopped after the first of the sizes above 3 that finds anything.
//
// An expression is a code: one base-3 digit per condition, the first condition the most significant, 0 not in it, 1 negated (level 0), 2 present (level 1).
//
// Not here: multi-value conditions, the add argument and the membership scores of the expressions.

use e.mem

// the results: per expression its kind (0 conjunction, 1 disjunction), code, inclusion, PRI (sufficiency) or RoN (necessity) and coverage
type Found = struct { kind: []u8, code: []usize, incl: []f64, pri: []f64, cov: []f64, count: usize }

// every literal of the earlier expression is in the later one
fn contained(early: []const u8, late: []const u8) -> bool {
    var c = 0usize
    while c < early.len {
        if early[c] != 0u8 && early[c] != late[c] { ret false }
        c += 1usize
    }
    ret true
}

fn record(code: []usize, lits: []u8, at: usize, level: []const u8) {
    var v = 0usize
    var c = 0usize
    while c < level.len {
        v = v * 3usize + usize(level[c])
        lits[at * level.len + c] = level[c]
        c += 1usize
    }
    code[at] = v
}

// x is n rows by k columns row-major, fz[c] 1 for a fuzzy column (negation is 1 - x), 0 for a crisp one (a literal matches the 0/1 value); y the outcome.
// incl_cut and cov_cut are the values QCA hands to its C code (R lowers incl.cut by the square root of the machine epsilon) (the caller drops the expressions whose PRI or RoN is below its own cut).
// nec 1 for the necessity search, 0 for sufficiency; depth 0 means all the conditions.
fn super_subset(a: *mem.Arena, x: []const f64, n: usize, k: usize, fz: []const u8, y: []const f64, nec: bool, incl_cut: f64, cov_cut: f64, depth: usize, f: *Found) -> err {
    var maxrows = 1usize
    var c0 = 0usize
    while c0 < k {
        maxrows *= 3usize
        c0 += 1usize
    }
    let (kind, e1) = mem.alloc[u8](a, maxrows)
    if e1 != ok { ret e1 }
    let (code, e2) = mem.alloc[usize](a, maxrows)
    if e2 != ok { ret e2 }
    let (incl, e3) = mem.alloc[f64](a, maxrows)
    if e3 != ok { ret e3 }
    let (pri, e4) = mem.alloc[f64](a, maxrows)
    if e4 != ok { ret e4 }
    let (cov, e5) = mem.alloc[f64](a, maxrows)
    if e5 != ok { ret e5 }
    // the literals of each found expression, for the redundancy tests: per found one level per condition (0 absent)
    let (lits, e6) = mem.alloc[u8](a, maxrows * k)
    if e6 != ok { ret e6 }
    var dep = depth
    if dep == 0usize || dep > k { dep = k }
    var so = 0.0f64
    var r = 0usize
    while r < n {
        so += y[r]
        r += 1usize
    }
    var found = 0usize
    var foundk1 = 0usize
    var level: [16]u8 = zero
    var sel: [16]usize = zero
    var stop = false
    var kk = 1usize
    while kk <= dep && !stop {
        if found > 0usize && kk > 3usize { stop = true }
        // every k-subset of the conditions in lexicographic order
        var i = 0usize
        while i < kk {
            sel[i] = i
            i += 1usize
        }
        var more = true
        while more {
            // every level combination, the first chosen condition varying slowest
            var combos = 1usize
            i = 0usize
            while i < kk {
                combos *= 2usize
                i += 1usize
            }
            var cmb = 0usize
            while cmb < combos {
                var c = 0usize
                while c < k {
                    level[c] = 0u8
                    c += 1usize
                }
                i = 0usize
                while i < kk {
                    let shift = kk - 1usize - i
                    level[sel[i]] = u8(((cmb >> shift) & 1usize) + 1usize)
                    i += 1usize
                }
                var smin = 0.0f64
                var smax = 0.0f64
                var smin_y_min = 0.0f64
                var smin_y_max = 0.0f64
                var pri_min = 0.0f64
                var pri_max = 0.0f64
                var s1min = 0.0f64
                var s1max = 0.0f64
                var s1y_min = 0.0f64
                var s1y_max = 0.0f64
                r = 0usize
                while r < n {
                    var mn = 1000000.0f64
                    var mx = 0.0f64
                    c = 0usize
                    while c < k {
                        if level[c] != 0u8 {
                            var v = x[r * k + c]
                            if fz[c] == 1u8 {
                                if level[c] == 1u8 { v = 1.0f64 - v }
                            } else {
                                if f64(level[c]) == v + 1.0f64 {
                                    v = 1.0f64
                                } else {
                                    v = 0.0f64
                                }
                            }
                            if v < mn { mn = v }
                            if v > mx { mx = v }
                        }
                        c += 1usize
                    }
                    let yy = y[r]
                    smin += mn
                    smax += mx
                    var ymn = mn
                    if yy < ymn { ymn = yy }
                    var ymx = mx
                    if yy < ymx { ymx = yy }
                    smin_y_min += ymn
                    smin_y_max += ymx
                    if nec {
                        s1min += 1.0f64 - mn
                        s1max += 1.0f64 - mx
                        s1y_min += 1.0f64 - ymn
                        s1y_max += 1.0f64 - ymx
                    } else {
                        var t12 = 1.0f64 - yy
                        if ymn < t12 { t12 = ymn }
                        pri_min += t12
                        var t22 = 1.0f64 - mx
                        if ymx < t22 { t22 = ymx }
                        pri_max += t22
                    }
                    r += 1usize
                }
                var iv: [6]f64 = zero
                if !(smin_y_min == 0.0f64 && smin == 0.0f64) { iv[0usize] = smin_y_min / smin }
                if !(smin_y_min == 0.0f64 && so == 0.0f64) { iv[1usize] = smin_y_min / so }
                if !(smin_y_max == 0.0f64 && so == 0.0f64) { iv[2usize] = smin_y_max / so }
                if !(smin_y_max == 0.0f64 && smax == 0.0f64) { iv[3usize] = smin_y_max / smax }
                if nec {
                    if !(s1min == 0.0f64 && s1y_min == 0.0f64) { iv[4usize] = s1min / s1y_min }
                    if !(s1max == 0.0f64 && s1y_max == 0.0f64) { iv[5usize] = s1max / s1y_max }
                } else {
                    let a1 = smin_y_min - pri_min
                    let a2 = smin - pri_min
                    if !(a1 == 0.0f64 && a2 == 0.0f64) { iv[4usize] = a1 / a2 }
                    let b1 = smin_y_max - pri_max
                    let b2 = so - pri_max
                    if !(b1 == 0.0f64 && b2 == 0.0f64) { iv[5usize] = b1 / b2 }
                }
                var ci = 0usize
                var cc = 1usize
                if nec {
                    ci = 1usize
                    cc = 0usize
                }
                var redundant = false
                if iv[ci] >= incl_cut && iv[cc] >= cov_cut {
                    if !nec {
                        var q = 0usize
                        while q < foundk1 && !redundant {
                            if kind[q] == 0u8 && contained(lits[q * k..q * k + k], level[0usize..k]) { redundant = true }
                            q += 1usize
                        }
                    }
                    if !redundant {
                        kind[found] = 0u8
                        incl[found] = iv[ci]
                        pri[found] = iv[4usize]
                        cov[found] = iv[cc]
                        record(code, lits, found, level[0usize..k])
                        found += 1usize
                    }
                } else if nec {
                    if iv[2usize] >= incl_cut && iv[3usize] >= cov_cut {
                        var q = 0usize
                        while q < foundk1 && !redundant {
                            if contained(lits[q * k..q * k + k], level[0usize..k]) { redundant = true }
                            q += 1usize
                        }
                        if !redundant {
                            kind[found] = 1u8
                            incl[found] = iv[2usize]
                            pri[found] = iv[5usize]
                            cov[found] = iv[3usize]
                            record(code, lits, found, level[0usize..k])
                            found += 1usize
                        }
                    }
                }
                cmb += 1usize
            }
            // the next subset
            var p = kk
            var moved = false
            while p > 0usize && !moved {
                p -= 1usize
                if sel[p] < k - kk + p {
                    sel[p] += 1usize
                    var q = p + 1usize
                    while q < kk {
                        sel[q] = sel[q - 1usize] + 1usize
                        q += 1usize
                    }
                    moved = true
                }
            }
            if !moved { more = false }
        }
        foundk1 = found
        kk += 1usize
    }
    f.kind = kind
    f.code = code
    f.incl = incl
    f.pri = pri
    f.cov = cov
    f.count = found
    ret ok
}
