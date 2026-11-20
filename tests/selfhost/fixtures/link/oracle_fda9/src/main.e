// e.algo.stat.fdafr against fda. tests/oracle/fda9.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda9`; the layout is at the top of scripts/r_oracle/groups/fda9.R.

use e.algo.stat.fdafr as ff
use e.algo.stat.fdapkg as fa
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    // F: (index, N, noy, nbry, p, [type, nox, nbrx, nob, nbrb, lambda] x p, ybreaks, ycoefs, then per covariate xbreaks, bbreaks, xcoefs)
    let nrep = usize(z[1usize])
    let noy = usize(z[2usize])
    let nbry = usize(z[3usize])
    let p = usize(z[4usize])
    let nby = nbry + noy - 2usize
    let h0 = 5usize
    let y0 = h0 + 6usize * p
    let yc0 = y0 + nbry
    var at = yc0 + nby * nrep
    let yb = fa.Bspec{ kind: 0usize, period: 0.0f64, par: z[0usize..0usize], norder: noy, breaks: z[y0..y0 + nbry] }
    let (xs, e1) = mem.alloc[fa.Bspec](a, p)
    let (bs, e2) = mem.alloc[fa.Bspec](a, p)
    let (lam, e3) = mem.alloc[f64](a, p)
    let (rr, e4) = mem.alloc[f64](a, 2usize)
    var total = 0usize
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    rr[0usize] = z[y0]
    rr[1usize] = z[y0 + nbry - 1usize]
    var xoff = at
    var j = 0usize
    while j < p {
        let h = h0 + 6usize * j
        let kind = usize(z[h])
        lam[j] = z[h + 5usize]
        if kind == 0usize {
            xs[j] = fa.Bspec{ kind: 5usize, period: 0.0f64, par: z[0usize..0usize], norder: 1usize, breaks: rr }
            bs[j] = fa.Bspec{ kind: 5usize, period: 0.0f64, par: z[0usize..0usize], norder: 1usize, breaks: rr }
            total += 1usize
            at += nrep
        } else {
            let nox = usize(z[h + 1usize])
            let nbrx = usize(z[h + 2usize])
            let nob = usize(z[h + 3usize])
            let nbrb = usize(z[h + 4usize])
            xs[j] = fa.Bspec{ kind: 0usize, period: 0.0f64, par: z[0usize..0usize], norder: nox, breaks: z[at..at + nbrx] }
            bs[j] = fa.Bspec{ kind: 0usize, period: 0.0f64, par: z[0usize..0usize], norder: nob, breaks: z[at + nbrx..at + nbrx + nbrb] }
            total += nbrb + nob - 2usize
            at += nbrx + nbrb + (nbrx + nox - 2usize) * nrep
        }
        j += 1usize
    }
    // the covariate coefficient blocks sit after their breaks, so gather them into one array
    let (xc, e5) = mem.alloc[f64](a, at - xoff)
    let (o, e6) = mem.alloc[f64](a, total)
    if e5 != ok || e6 != ok { ret nan }
    var w = 0usize
    var pos = xoff
    j = 0usize
    while j < p {
        let h = h0 + 6usize * j
        var cn = nrep
        if usize(z[h]) == 1usize {
            let nbrx = usize(z[h + 2usize])
            let nbrb = usize(z[h + 4usize])
            pos += nbrx + nbrb
            cn = (nbrx + usize(z[h + 1usize]) - 2usize) * nrep
        }
        var k = 0usize
        while k < cn {
            xc[w + k] = z[pos + k]
            k += 1usize
        }
        w += cn
        pos += cn
        j += 1usize
    }
    if ff.fregress_fd(a, nrep, &yb, z[yc0..yc0 + nby * nrep], p, xs, xc[0usize..w], bs, lam, o) != ok { ret nan }
    ret o[usize(z[0usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda9.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
