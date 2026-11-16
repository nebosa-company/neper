// R ggm, the construction of ancestral graphs by marginalisation and conditioning: RG (the regression graph), SG (the summary graph), AG (the ancestral graph), Max (the maximal ancestral graph of an ancestral one) and MAG = Max(AG), as the package's loops do them. A mixed graph is an n by n matrix of integers, row-major, whose entry (i, j) holds 1 for an arrow, 10 for a line and 100 for an arc, added (makeMG builds one); M lists the vertices marginalised over and C those conditioned on, 0-based. The result drops the rows and columns of M and C.
//
// The package's loops are reproduced literally, including that assigning TRUE overwrites a cell with 1 and that the
// matrix is changed while a later test reads it.

use e.mem

// the rows r with the entry (r, col) of the matrix satisfying mode: 0 entry mod 10 = 1, 1 entry > 99, 2 entry mod 100 > 9
fn col_rows(m: []const i64, n: usize, col: usize, mode: usize, out: []usize) -> usize {
    var c = 0usize
    var r = 0usize
    while r < n {
        let v = m[r * n + col]
        var ok_ = false
        if mode == 0usize { ok_ = v % 10i64 == 1i64 }
        if mode == 1usize { ok_ = v > 99i64 }
        if mode == 2usize { ok_ = v % 100i64 > 9i64 }
        if ok_ {
            out[c] = r
            c += 1usize
        }
        r += 1usize
    }
    ret c
}

fn transpose(m: []const i64, n: usize, out: []i64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[j * n + i] = m[i * n + j]
            j += 1usize
        }
        i += 1usize
    }
}

fn add_into(dst: []i64, src: []const i64, nn: usize) {
    var i = 0usize
    while i < nn {
        dst[i] += src[i]
        i += 1usize
    }
}

fn same(a: []const i64, b: []const i64) -> bool {
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// the vertices of the set `start` and all their parents (cells mod 10 = 1 of a column), as a flag per vertex
fn closure(m: []const i64, n: usize, start: []const bool, out: []bool) {
    var i = 0usize
    while i < n {
        out[i] = start[i]
        i += 1usize
    }
    var go = true
    while go {
        go = false
        var j = 0usize
        while j < n {
            if out[j] {
                var r = 0usize
                while r < n {
                    if m[r * n + j] % 10i64 == 1i64 && !out[r] {
                        out[r] = true
                        go = true
                    }
                    r += 1usize
                }
            }
            j += 1usize
        }
    }
}

// level 0 RG, 1 SG, 2 AG; answers the n by n matrix before the vertices of M and C are dropped
fn ag_full(a: *mem.Arena, amat: []const i64, n: usize, mv: []const usize, cv: []const usize, level: usize) -> ([]i64, err) {
    let nn = n * n
    let (r, e0) = mem.alloc[i64](a, nn)
    let (t, e1) = mem.alloc[i64](a, nn)
    let (n2, e2) = mem.alloc[i64](a, nn)
    let (x31, e3) = mem.alloc[i64](a, nn)
    let (tm, e4) = mem.alloc[i64](a, nn)
    let (idx, e5) = mem.alloc[usize](a, n)
    let (idy, e6) = mem.alloc[usize](a, n)
    let (sset, e7) = mem.alloc[bool](a, n)
    let (cflag, e8) = mem.alloc[bool](a, n)
    let (rn, e9) = mem.alloc[i64](a, nn)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (r, mem.Full) }
    var i = 0usize
    while i < n {
        cflag[i] = false
        i += 1usize
    }
    i = 0usize
    while i < cv.len {
        cflag[cv[i]] = true
        i += 1usize
    }
    closure(amat, n, cflag, sset)
    i = 0usize
    while i < nn {
        r[i] = amat[i]
        t[i] = 2i64 * amat[i]
        i += 1usize
    }
    while !same(r, t) {
        i = 0usize
        while i < nn {
            t[i] = r[i]
            n2[i] = r[i]
            i += 1usize
        }
        // step 1: marginalisation over the vertices of M
        var q = 0usize
        while q < mv.len {
            let kk = mv[q]
            var kkk = 0usize
            while kkk < n {
                i = 0usize
                while i < nn {
                    x31[i] = r[i]
                    i += 1usize
                }
                if r[kkk * n + kk] % 10i64 == 1i64 || r[kk * n + kkk] % 10i64 == 1i64 {
                    x31[kk * n + kkk] = r[kkk * n + kk]
                    x31[kkk * n + kk] = r[kk * n + kkk]
                }
                let ni = col_rows(x31, n, kk, 0usize, idx)
                if ni > 1usize && x31[kkk * n + kk] % 10i64 == 1i64 {
                    var ii = 0usize
                    while ii < ni {
                        if r[idx[ii] * n + kkk] % 10i64 == 0i64 && idx[ii] != kkk { n2[idx[ii] * n + kkk] = 1i64 }
                        ii += 1usize
                    }
                }
                kkk += 1usize
            }
            q += 1usize
        }
        i = 0usize
        while i < nn {
            r[i] = n2[i]
            n2[i] = 0i64
            i += 1usize
        }
        // step 2: the conditioned set
        var kq = 0usize
        while kq < n {
            if sset[kq] {
                let ni = col_rows(r, n, kq, 0usize, idx)
                let nj = col_rows(r, n, kq, 1usize, idy)
                if ni > 0usize && nj > 0usize {
                    var ii = 0usize
                    while ii < ni {
                        var jj = 0usize
                        while jj < nj {
                            if r[idx[ii] * n + idy[jj]] % 10i64 == 0i64 && idx[ii] != idy[jj] { n2[idx[ii] * n + idy[jj]] = 1i64 }
                            jj += 1usize
                        }
                        ii += 1usize
                    }
                }
            }
            kq += 1usize
        }
        add_into(r, n2, nn)
        // step 3
        transpose(r, n, tm)
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let kk = mv[q]
            let ni = col_rows(tm, n, kk, 0usize, idx)
            let nj = col_rows(tm, n, kk, 2usize, idy)
            if ni > 0usize && nj > 0usize {
                var ii = 0usize
                while ii < ni {
                    var jj = 0usize
                    while jj < nj {
                        if r[idy[jj] * n + idx[ii]] % 10i64 == 0i64 && idx[ii] != idy[jj] { n2[idy[jj] * n + idx[ii]] = 1i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        add_into(r, n2, nn)
        // step 4
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let kk = mv[q]
            let ni = col_rows(r, n, kk, 2usize, idx)
            let nj = col_rows(r, n, kk, 1usize, idy)
            if ni > 0usize && nj > 0usize {
                var ii = 0usize
                while ii < ni {
                    var jj = 0usize
                    while jj < nj {
                        if r[idx[ii] * n + idy[jj]] % 10i64 == 0i64 && idx[ii] != idy[jj] { n2[idx[ii] * n + idy[jj]] = 1i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        add_into(r, n2, nn)
        // step 5: two parents of a marginalised vertex get an arc
        transpose(r, n, tm)
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let ni = col_rows(tm, n, mv[q], 0usize, idx)
            if ni > 1usize {
                var ii = 0usize
                while ii + 1usize < ni {
                    var jj = ii + 1usize
                    while jj < ni {
                        if r[idx[ii] * n + idx[jj]] < 100i64 { n2[idx[ii] * n + idx[jj]] = 100i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
        // step 6
        transpose(r, n, tm)
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let kk = mv[q]
            let ni = col_rows(tm, n, kk, 0usize, idx)
            let nj = col_rows(tm, n, kk, 1usize, idy)
            if ni > 0usize && nj > 0usize {
                var ii = 0usize
                while ii < ni {
                    var jj = 0usize
                    while jj < nj {
                        if r[idy[jj] * n + idx[ii]] < 100i64 && idx[ii] != idy[jj] { n2[idy[jj] * n + idx[ii]] = 100i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
        // step 7: arcs among the vertices joined by arcs to a conditioned vertex
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        kq = 0usize
        while kq < n {
            if sset[kq] {
                let ni = col_rows(r, n, kq, 1usize, idx)
                if ni > 1usize {
                    var ii = 0usize
                    while ii + 1usize < ni {
                        var jj = ii + 1usize
                        while jj < ni {
                            if r[idx[ii] * n + idx[jj]] < 100i64 { n2[idx[ii] * n + idx[jj]] = 100i64 }
                            jj += 1usize
                        }
                        ii += 1usize
                    }
                }
            }
            kq += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
        // step 8: lines among the parents of a conditioned vertex
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        kq = 0usize
        while kq < n {
            if sset[kq] {
                let ni = col_rows(r, n, kq, 0usize, idx)
                if ni > 1usize {
                    var ii = 0usize
                    while ii + 1usize < ni {
                        var jj = ii + 1usize
                        while jj < ni {
                            if r[idx[ii] * n + idx[jj]] % 100i64 < 10i64 { n2[idx[ii] * n + idx[jj]] = 10i64 }
                            jj += 1usize
                        }
                        ii += 1usize
                    }
                }
            }
            kq += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
        // step 9
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let kk = mv[q]
            let ni = col_rows(r, n, kk, 0usize, idx)
            let nj = col_rows(r, n, kk, 2usize, idy)
            if ni > 0usize && nj > 0usize {
                var ii = 0usize
                while ii < ni {
                    var jj = 0usize
                    while jj < nj {
                        if r[idx[ii] * n + idy[jj]] % 100i64 < 10i64 && idx[ii] != idy[jj] { n2[idx[ii] * n + idy[jj]] = 10i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
        // step 10
        i = 0usize
        while i < nn {
            n2[i] = 0i64
            i += 1usize
        }
        q = 0usize
        while q < mv.len {
            let ni = col_rows(r, n, mv[q], 2usize, idx)
            if ni > 1usize {
                var ii = 0usize
                while ii + 1usize < ni {
                    var jj = ii + 1usize
                    while jj < ni {
                        if r[idx[ii] * n + idx[jj]] % 100i64 < 10i64 { n2[idx[ii] * n + idx[jj]] = 10i64 }
                        jj += 1usize
                    }
                    ii += 1usize
                }
            }
            q += 1usize
        }
        transpose(n2, n, tm)
        add_into(n2, tm, nn)
        add_into(r, n2, nn)
    }
    if level >= 1usize {
        var ci = 0usize
        while ci < n {
            var cj = 0usize
            while cj < n {
                if r[ci * n + cj] % 100i64 > 9i64 {
                    r[ci * n + cj] = 10i64
                    var ck = 0usize
                    while ck < n {
                        if r[ck * n + cj] == 100i64 {
                            r[cj * n + ck] = 1i64
                            r[ck * n + cj] = 0i64
                        }
                        ck += 1usize
                    }
                }
                cj += 1usize
            }
            ci += 1usize
        }
        var ss: []bool = sset
        let (ss2, es) = mem.alloc[bool](a, n)
        if es != ok { ret (r, es) }
        closure(r, n, sset, ss2)
        ss = ss2
        ci = 0usize
        while ci < n {
            if ss[ci] {
                var cj = 0usize
                while cj < n {
                    if ss[cj] && r[ci * n + cj] % 10i64 == 1i64 {
                        r[ci * n + cj] = 10i64
                        r[cj * n + ci] = 10i64
                    }
                    cj += 1usize
                }
            }
            ci += 1usize
        }
    }
    if level == 2usize {
        i = 0usize
        while i < nn {
            rn[i] = r[i]
            i += 1usize
        }
        var kk = 0usize
        while kk < n {
            var kkk = 0usize
            while kkk < n {
                i = 0usize
                while i < nn {
                    x31[i] = r[i]
                    i += 1usize
                }
                if r[kkk * n + kk] % 10i64 == 1i64 || r[kk * n + kkk] % 10i64 == 1i64 {
                    x31[kk * n + kkk] = r[kkk * n + kk]
                    x31[kkk * n + kk] = r[kk * n + kkk]
                }
                let ni = col_rows(x31, n, kk, 0usize, idx)
                if ni > 1usize && x31[kkk * n + kk] % 10i64 == 1i64 {
                    var ii = 0usize
                    while ii < ni {
                        if r[idx[ii] * n + kkk] % 10i64 == 0i64 && idx[ii] != kkk { rn[idx[ii] * n + kkk] = 1i64 }
                        ii += 1usize
                    }
                }
                kkk += 1usize
            }
            kk += 1usize
        }
        i = 0usize
        while i < nn {
            t[i] = 2i64 * amat[i]
            i += 1usize
        }
        while !same(r, t) {
            i = 0usize
            while i < nn {
                t[i] = r[i]
                n2[i] = 0i64
                i += 1usize
            }
            var k2 = 0usize
            while k2 < n {
                let ni = col_rows(rn, n, k2, 1usize, idx)
                if ni > 1usize {
                    var ii = 0usize
                    while ii + 1usize < ni {
                        var jj = ii + 1usize
                        while jj < ni {
                            if r[idx[ii] * n + idx[jj]] < 100i64 && (rn[k2 * n + idx[ii]] % 10i64 == 1i64 || rn[k2 * n + idx[jj]] % 10i64 == 1i64) { n2[idx[ii] * n + idx[jj]] = 100i64 }
                            jj += 1usize
                        }
                        ii += 1usize
                    }
                }
                k2 += 1usize
            }
            transpose(n2, n, tm)
            add_into(n2, tm, nn)
            add_into(rn, n2, nn)
            add_into(r, n2, nn)
            i = 0usize
            while i < nn {
                n2[i] = 0i64
                i += 1usize
            }
            k2 = 0usize
            while k2 < n {
                let ni = col_rows(rn, n, k2, 0usize, idx)
                let nj = col_rows(rn, n, k2, 1usize, idy)
                if ni > 0usize && nj > 0usize {
                    var ii = 0usize
                    while ii < ni {
                        var jj = 0usize
                        while jj < nj {
                            if r[idx[ii] * n + idy[jj]] % 10i64 == 0i64 && idx[ii] != idy[jj] && rn[k2 * n + idy[jj]] % 10i64 == 1i64 { n2[idx[ii] * n + idy[jj]] = 1i64 }
                            jj += 1usize
                        }
                        ii += 1usize
                    }
                }
                k2 += 1usize
            }
            add_into(rn, n2, nn)
            add_into(r, n2, nn)
        }
        var ci = 0usize
        while ci < n {
            var cj = 0usize
            while cj < n {
                if r[ci * n + cj] == 101i64 {
                    r[ci * n + cj] = 1i64
                    r[cj * n + ci] = 0i64
                }
                cj += 1usize
            }
            ci += 1usize
        }
    }
    ret (r, ok)
}

// the matrix without the rows and columns of M and C; answers the new size
fn drop_vertices(m: []const i64, n: usize, mv: []const usize, cv: []const usize, out: []i64) -> usize {
    var keep: [64]usize = zero
    var nk = 0usize
    var v = 0usize
    while v < n {
        var gone = false
        var q = 0usize
        while q < mv.len {
            if mv[q] == v { gone = true }
            q += 1usize
        }
        q = 0usize
        while q < cv.len {
            if cv[q] == v { gone = true }
            q += 1usize
        }
        if !gone {
            keep[nk] = v
            nk += 1usize
        }
        v += 1usize
    }
    var i = 0usize
    while i < nk {
        var j = 0usize
        while j < nk {
            out[i * nk + j] = m[keep[i] * n + keep[j]]
            j += 1usize
        }
        i += 1usize
    }
    ret nk
}

// ggm::AG (level 2), SG (1) or RG (0): the graph over the vertices left after marginalising over mv and conditioning on cv; out is n * n long and the first k * k entries are filled, k answered
fn ag(a: *mem.Arena, amat: []const i64, n: usize, mv: []const usize, cv: []const usize, level: usize, out: []i64) -> (usize, err) {
    let (r, e) = ag_full(a, amat, n, mv, cv, level)
    if e != ok { ret (0usize, e) }
    ret (drop_vertices(r, n, mv, cv, out), ok)
}


// the ordered ancestor vector of ggm::Max: S starts as (one, two); each pass visits the vertices of a snapshot of S and moves every parent found to the front, until a pass leaves S unchanged
fn ordered_closure(m: []const i64, n: usize, one: usize, two: usize, s: []usize, snap: []usize, prev: []usize) -> usize {
    var ns = 2usize
    s[0usize] = one
    s[1usize] = two
    var go = true
    while go {
        let np = ns
        var q = 0usize
        while q < ns {
            prev[q] = s[q]
            snap[q] = s[q]
            q += 1usize
        }
        var sn = ns
        q = 0usize
        while q < np {
            let j = snap[q]
            var i = 0usize
            while i < n {
                if m[i * n + j] % 10i64 == 1i64 {
                    var others: [64]usize = zero
                    var w = 0usize
                    var r = 0usize
                    while r < sn {
                        if s[r] != i {
                            others[w] = s[r]
                            w += 1usize
                        }
                        r += 1usize
                    }
                    s[0usize] = i
                    r = 0usize
                    while r < w {
                        s[1usize + r] = others[r]
                        r += 1usize
                    }
                    sn = w + 1usize
                }
                i += 1usize
            }
            q += 1usize
        }
        ns = sn
        go = false
        if ns != np {
            go = true
        } else {
            q = 0usize
            while q < ns {
                if s[q] != prev[q] { go = true }
                q += 1usize
            }
        }
    }
    ret ns
}

fn remove_all(v: []usize, len: usize, x: usize) -> usize {
    var w = 0usize
    var i = 0usize
    while i < len {
        if v[i] != x {
            v[w] = v[i]
            w += 1usize
        }
        i += 1usize
    }
    ret w
}

// ggm::Max: the maximal ancestral graph of the ancestral graph m (n by n), in place
fn max_graph(a: *mem.Arena, m: []i64, n: usize) -> err {
    let cap = n * n + 4usize
    let (s, e1) = mem.alloc[usize](a, cap)
    let (snap, e2) = mem.alloc[usize](a, cap)
    let (prev, e3) = mem.alloc[usize](a, cap)
    let (sr, e4) = mem.alloc[usize](a, cap)
    let (oa, e5) = mem.alloc[usize](a, cap)
    let (oc, e6) = mem.alloc[usize](a, cap)
    let (ta, e7) = mem.alloc[usize](a, cap)
    let (tc, e8) = mem.alloc[usize](a, cap)
    let (na_, e9) = mem.alloc[usize](a, cap)
    let (nc_, e10) = mem.alloc[usize](a, cap)
    let (nta, e11) = mem.alloc[usize](a, cap)
    let (ntc, e12) = mem.alloc[usize](a, cap)
    let (ats, e13) = mem.alloc[usize](a, 2usize * cap)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret mem.Full }
    var nat = 0usize
    var cj = 0usize
    while cj < n {
        var ri = 0usize
        while ri < n {
            var dg = 0i64
            if ri == cj { dg = 1i64 }
            if m[ri * n + cj] + m[cj * n + ri] + dg == 0i64 {
                ats[2usize * nat] = ri
                ats[2usize * nat + 1usize] = cj
                nat += 1usize
            }
            ri += 1usize
        }
        cj += 1usize
    }
    var ip = 0usize
    while ip < nat {
        let one = ats[2usize * ip]
        let two = ats[2usize * ip + 1usize]
        let ns = ordered_closure(m, n, one, two, s, snap, prev)
        var nsr = 0usize
        var i = 0usize
        while i < ns {
            if s[i] != one && s[i] != two {
                sr[nsr] = s[i]
                nsr += 1usize
            }
            i += 1usize
        }
        var noa = 0usize
        var noc = 0usize
        var nta_ = 0usize
        var ntc_ = 0usize
        if nsr > 0usize {
            var q = 0usize
            while q < nsr {
                let j = sr[q]
                if m[one * n + j] % 10i64 == 1i64 {
                    oa[noa] = j
                    noa += 1usize
                }
                if m[one * n + j] > 99i64 {
                    oc[noc] = j
                    noc += 1usize
                }
                q += 1usize
            }
            q = 0usize
            while q < nsr {
                let j = sr[q]
                if m[two * n + j] % 10i64 == 1i64 {
                    var k = 0usize
                    while k < noc {
                        if j == oc[k] || m[j * n + oc[k]] > 99i64 { m[two * n + one] = 1i64 }
                        k += 1usize
                    }
                    ta[nta_] = j
                    nta_ += 1usize
                }
                if m[two * n + j] > 99i64 {
                    var k = 0usize
                    while k < noa {
                        if j == oa[k] || m[j * n + oa[k]] > 99i64 { m[one * n + two] = 1i64 }
                        k += 1usize
                    }
                    k = 0usize
                    while k < noc {
                        if j == oc[k] || m[j * n + oc[k]] > 99i64 {
                            m[one * n + two] = 100i64
                            m[two * n + one] = 100i64
                        }
                        k += 1usize
                    }
                    tc[ntc_] = j
                    ntc_ += 1usize
                }
                q += 1usize
            }
        }
        if noc + noa + ntc_ + nta_ > 0usize {
            var q = 0usize
            while q < noc {
                nsr = remove_all(sr, nsr, oc[q])
                q += 1usize
            }
            q = 0usize
            while q < noa {
                nsr = remove_all(sr, nsr, oa[q])
                q += 1usize
            }
            q = 0usize
            while q < ntc_ {
                nsr = remove_all(sr, nsr, tc[q])
                q += 1usize
            }
            q = 0usize
            while q < nta_ {
                nsr = remove_all(sr, nsr, ta[q])
                q += 1usize
            }
            var more = true
            while more && nsr > 0usize {
                var nnoc = 0usize
                var nnoa = 0usize
                var nntc = 0usize
                var nnta = 0usize
                q = 0usize
                while q < noc {
                    let l = oc[q]
                    var w = 0usize
                    while w < nsr {
                        if m[l * n + sr[w]] > 99i64 {
                            nc_[nnoc] = sr[w]
                            nnoc += 1usize
                        }
                        w += 1usize
                    }
                    q += 1usize
                }
                q = 0usize
                while q < noa {
                    let l = oa[q]
                    var w = 0usize
                    while w < nsr {
                        if m[l * n + sr[w]] > 99i64 {
                            na_[nnoa] = sr[w]
                            nnoa += 1usize
                        }
                        w += 1usize
                    }
                    q += 1usize
                }
                q = 0usize
                while q < ntc_ {
                    let l = tc[q]
                    var w = 0usize
                    while w < nsr {
                        let j = sr[w]
                        if m[l * n + j] > 99i64 {
                            var k = 0usize
                            while k < noa {
                                if j == oa[k] || m[j * n + oa[k]] > 99i64 { m[one * n + two] = 1i64 }
                                k += 1usize
                            }
                            k = 0usize
                            while k < noc {
                                if j == oc[k] || m[j * n + oc[k]] > 99i64 {
                                    m[one * n + two] = 100i64
                                    m[two * n + one] = 100i64
                                }
                                k += 1usize
                            }
                            ntc[nntc] = j
                            nntc += 1usize
                        }
                        w += 1usize
                    }
                    q += 1usize
                }
                q = 0usize
                while q < nta_ {
                    let l = ta[q]
                    var w = 0usize
                    while w < nsr {
                        let j = sr[w]
                        if m[l * n + j] > 99i64 {
                            var k = 0usize
                            while k < noc {
                                if j == oc[k] || m[j * n + oc[k]] > 99i64 {
                                    m[one * n + two] = 100i64
                                    m[two * n + one] = 100i64
                                }
                                k += 1usize
                            }
                            nta[nnta] = j
                            nnta += 1usize
                        }
                        w += 1usize
                    }
                    q += 1usize
                }
                if nnoc + nnoa + nntc + nnta == 0usize {
                    more = false
                } else {
                    q = 0usize
                    while q < nnoc {
                        nsr = remove_all(sr, nsr, nc_[q])
                        q += 1usize
                    }
                    q = 0usize
                    while q < nnoa {
                        nsr = remove_all(sr, nsr, na_[q])
                        q += 1usize
                    }
                    q = 0usize
                    while q < nntc {
                        nsr = remove_all(sr, nsr, ntc[q])
                        q += 1usize
                    }
                    q = 0usize
                    while q < nnta {
                        nsr = remove_all(sr, nsr, nta[q])
                        q += 1usize
                    }
                    q = 0usize
                    while q < nnoc {
                        oc[q] = nc_[q]
                        q += 1usize
                    }
                    noc = nnoc
                    q = 0usize
                    while q < nntc {
                        tc[q] = ntc[q]
                        q += 1usize
                    }
                    ntc_ = nntc
                    q = 0usize
                    while q < nnoa {
                        oa[q] = na_[q]
                        q += 1usize
                    }
                    noa = nnoa
                    q = 0usize
                    while q < nnta {
                        ta[q] = nta[q]
                        q += 1usize
                    }
                    nta_ = nnta
                }
            }
        }
        ip += 1usize
    }
    ret ok
}

// ggm::MAG (level 2), MSG (1) or MRG (0): Max of AG, SG or RG: the maximal ancestral graph of the graph over the vertices left after marginalising over mv and conditioning on cv; out is n * n long and the first k * k entries are filled, k answered
fn mag(a: *mem.Arena, amat: []const i64, n: usize, mv: []const usize, cv: []const usize, level: usize, out: []i64) -> (usize, err) {
    let (k, e) = ag(a, amat, n, mv, cv, level, out)
    if e != ok { ret (0usize, e) }
    let em = max_graph(a, out[0usize..k * k], k)
    ret (k, em)
}
