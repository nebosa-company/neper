// R e1071::matchClasses: the pairing of the classes of two labelings from their contingency table, by the row
// maximum, by random greedy search (R's stream) or by the exact search over every permutation in the order of
// e1071's `permutations`. Tables are row-major, rows by columns; answers 0-based columns.
//
// Not here: the verbose printing, compareMatchedClasses (a loop over matchClasses and classAgreement).

use e.algo.rand.r as rng
use e.mem

// e1071::permutations(n): n! rows of n 1-based values in the package's order, row-major
fn permutations(a: *mem.Arena, n: usize, out: []usize) {
    let (a1, e1) = mem.alloc[usize](a, out.len + 1usize)
    if e1 != ok { ret }
    // z holds the rows built so far, `rows` of them, `cols` wide
    out[0usize] = 1usize
    var rows = 1usize
    var cols = 1usize
    var i = 2usize
    while i <= n {
        // x = cbind(z, i): rows by cols + 1
        let w = cols + 1usize
        var r = 0usize
        while r < rows {
            var c = 0usize
            while c < cols {
                a1[r * w + c] = out[r * cols + c]
                c += 1usize
            }
            a1[r * w + cols] = i
            r += 1usize
        }
        // z[j * rows + r, ] = x[r, a[1:i + j]] where a = c(1:i, 1:(i - 1)), j = 0 .. i - 1
        var j = 0usize
        while j < i {
            r = 0usize
            while r < rows {
                var c = 0usize
                while c < w {
                    // column c + j of a: a is 1..i then 1..i-1
                    let src = (c + j) % i
                    out[(j * rows + r) * w + c] = a1[r * w + src]
                    c += 1usize
                }
                r += 1usize
            }
            j += 1usize
        }
        rows = rows * i
        cols = w
        i += 1usize
    }
}

fn which_max_row(tab: []const f64, nr: usize, nc: usize, r: usize) -> usize {
    var best = 0usize
    var c = 1usize
    while c < nc {
        if tab[r * nc + c] > tab[r * nc + best] { best = c }
        c += 1usize
    }
    ret best
}

fn which_max_col(tab: []const f64, nr: usize, nc: usize, c: usize) -> usize {
    var best = 0usize
    var r = 1usize
    while r < nr {
        if tab[r * nc + c] > tab[best * nc + c] { best = r }
        r += 1usize
    }
    ret best
}

fn agreement(tab: []const f64, n: usize, ret_: []const usize) -> f64 {
    var d = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        d += tab[i * n + ret_[i]]
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        tot += tab[i]
        i += 1usize
    }
    ret d / tot
}

// method 0 rowmax, 1 greedy (iter random restarts), 2 exact (falls to greedy when more than maxexact rows are open); out has nr values
fn match_classes(a: *mem.Arena, g: *rng.Rng, tab: []const f64, nr: usize, nc: usize, method: u8, iter0: usize, maxexact: usize, out: []usize) -> err {
    var m = method
    var iter = iter0
    var i = 0usize
    if m == 0u8 {
        i = 0usize
        while i < nr {
            out[i] = which_max_row(tab, nr, nc, i)
            i += 1usize
        }
        ret ok
    }
    if nr != nc { ret NotSquare }
    let n = nr
    let (rmax, e1) = mem.alloc[usize](a, n)
    let (cmax, e2) = mem.alloc[usize](a, n)
    let (baseok, e3) = mem.alloc[bool](a, n)
    let (newret, e4) = mem.alloc[usize](a, n)
    let (ok_, e5) = mem.alloc[bool](a, n)
    let (rest, e6) = mem.alloc[usize](a, n)
    let (used, e7) = mem.alloc[bool](a, n)
    let (cand, e8) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
    i = 0usize
    while i < n {
        rmax[i] = which_max_row(tab, n, n, i)
        cmax[i] = which_max_col(tab, n, n, i)
        i += 1usize
    }
    i = 0usize
    while i < n { baseok[i] = cmax[rmax[i]] == i
        i += 1usize }
    var k = 0usize
    var first = true
    while k < n {
        if cmax[rmax[k]] == k {
            // the best sum of another entry of row k and another of column rmax[k] must stay below the entry
            var mx = 0.0f64
            var have = false
            var c = 0usize
            while c < n {
                if c != rmax[k] {
                    var r = 0usize
                    while r < n {
                        if r != k {
                            let s = tab[k * n + c] + tab[r * n + rmax[k]]
                            if !have || s > mx {
                                mx = s
                                have = true
                            }
                        }
                        r += 1usize
                    }
                }
                c += 1usize
            }
            if !have || mx < tab[k * n + rmax[k]] { out[k] = rmax[k] } else { baseok[k] = false }
        }
        k += 1usize
    }
    var nbad = 0usize
    i = 0usize
    while i < n {
        if !baseok[i] { nbad += 1usize }
        i += 1usize
    }
    if nbad == 0usize { ret ok }
    var perm: []usize = zero
    var nperm = 1usize
    if m == 2u8 {
        if nbad > maxexact {
            m = 1u8
        } else {
            nperm = 1usize
            var f = 2usize
            while f <= nbad {
                nperm = nperm * f
                f += 1usize
            }
            iter = nperm
            let (pm, pe) = mem.alloc[usize](a, nperm * nbad)
            if pe != ok { ret pe }
            permutations(a, nbad, pm)
            perm = pm
        }
    }
    // the columns not matched directly, ascending
    i = 0usize
    while i < n { used[i] = false
        i += 1usize }
    i = 0usize
    while i < n {
        if baseok[i] { used[out[i]] = true }
        i += 1usize
    }
    var nrest = 0usize
    i = 0usize
    while i < n {
        if !used[i] {
            rest[nrest] = i
            nrest += 1usize
        }
        i += 1usize
    }
    var oldagree = 0.0f64
    var l = 0usize
    while l < iter {
        i = 0usize
        while i < n {
            newret[i] = out[i]
            i += 1usize
        }
        if m == 1u8 {
            i = 0usize
            while i < n { ok_[i] = baseok[i]
                i += 1usize }
            while true {
                var nopen = 0usize
                i = 0usize
                while i < n {
                    if !ok_[i] {
                        cand[nopen] = i
                        nopen += 1usize
                    }
                    i += 1usize
                }
                if nopen <= 1usize { break }
                let (s, se) = rng.sample_int(a, g, i64(nopen), 1i64, false)
                if se != ok { ret se }
                let kk = cand[usize(s[0usize] - 1i64)]
                // the unmatched columns, the first maximum of row kk among them
                var best = n
                var c = 0usize
                while c < n {
                    var taken = false
                    var r = 0usize
                    while r < n {
                        if ok_[r] && newret[r] == c { taken = true }
                        r += 1usize
                    }
                    if !taken {
                        if best == n || tab[kk * n + c] > tab[kk * n + best] { best = c }
                    }
                    c += 1usize
                }
                newret[kk] = best
                ok_[kk] = true
            }
            // the one row left takes the one column left
            i = 0usize
            while i < n {
                if !ok_[i] {
                    var c = 0usize
                    while c < n {
                        var taken = false
                        var r = 0usize
                        while r < n {
                            if ok_[r] && newret[r] == c { taken = true }
                            r += 1usize
                        }
                        if !taken { newret[i] = c }
                        c += 1usize
                    }
                }
                i += 1usize
            }
        } else {
            var q = 0usize
            i = 0usize
            while i < n {
                if !baseok[i] {
                    newret[i] = rest[perm[l * nbad + q] - 1usize]
                    q += 1usize
                }
                i += 1usize
            }
        }
        let agree = agreement(tab, n, newret)
        if l > 0usize {
            if agree > oldagree {
                i = 0usize
                while i < n { out[i] = newret[i]
                    i += 1usize }
                oldagree = agree
            }
        } else {
            i = 0usize
            while i < n { out[i] = newret[i]
                i += 1usize }
            oldagree = agree
        }
        l += 1usize
    }
    ret ok
}

error NotSquare
