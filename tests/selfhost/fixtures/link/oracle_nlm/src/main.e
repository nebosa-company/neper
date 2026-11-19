// e.algo.stat.nlm (R's nlm, PORT) against R. tests/oracle/nlm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nlm`; the case layout is at the top of scripts/r_oracle/groups/nlm.R.

use e.algo.stat.nlm as nl
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Prob = struct { fid: usize, data: []const f64 }

fn objective(pr: *Prob, x: []const f64) -> f64 {
    let fid = pr.fid
    let n = x.len
    var s = 0.0f64
    var i = 0usize
    if fid == 1usize {
        let a = x[1usize] - x[0usize] * x[0usize]
        let b = 1.0f64 - x[0usize]
        ret 100.0f64 * a * a + b * b
    }
    if fid == 2usize {
        while i < n {
            let dd = x[i] - f64(i + 1usize)
            s = s + f64(i + 1usize) * dd * dd
            i += 1usize
        }
        ret s
    }
    if fid == 3usize {
        let s2 = math.exp[f64](x[0usize])
        let m = pr.data.len / 2usize
        while i < m {
            let w = s2 + pr.data[m + i]
            s = s + 0.5f64 * (math.log[f64](w) + pr.data[i] * pr.data[i] / w)
            i += 1usize
        }
        ret s
    }
    if fid == 4usize {
        let a = x[0usize] - 1.0f64
        let b = x[1usize] + 2.0f64
        let c = x[3usize] - x[0usize]
        ret a * a + b * b + c * c
    }
    if fid == 5usize {
        if x[0usize] > 2.5f64 { ret 1.0f64 / 0.0f64 }
        let a = x[0usize] - 3.0f64
        let b = x[1usize] + 1.0f64
        ret a * a + b * b
    }
    if fid == 6usize { ret math.abs[f64](x[0usize] - 1.0f64) + math.abs[f64](x[1usize] - 2.0f64) }
    if fid == 7usize {
        let a = x[0usize] + 10.0f64 * x[1usize]
        let b = x[2usize] - x[3usize]
        let c = x[1usize] - 2.0f64 * x[2usize]
        let e = x[0usize] - x[3usize]
        ret a * a + 5.0f64 * b * b + c * c * c * c + 10.0f64 * e * e * e * e
    }
    if fid == 8usize {
        let a = 1.5f64 - x[0usize] + x[0usize] * x[1usize]
        let b = 2.25f64 - x[0usize] + x[0usize] * (x[1usize] * x[1usize])
        let c = 2.625f64 - x[0usize] + x[0usize] * (x[1usize] * x[1usize] * x[1usize])
        ret a * a + b * b + c * c
    }
    if fid == 9usize {
        let a = x[0usize] * x[0usize] + x[1usize] - 11.0f64
        let b = x[0usize] + x[1usize] * x[1usize] - 7.0f64
        ret a * a + b * b
    }
    if fid == 10usize {
        let a = x[1usize] - x[0usize] * x[0usize]
        let b = 1.0f64 - x[0usize]
        let c = x[3usize] - x[2usize] * x[2usize]
        let e = 1.0f64 - x[2usize]
        ret 100.0f64 * a * a + b * b + 90.0f64 * c * c + e * e + 10.1f64 * ((x[1usize] - 1.0f64) * (x[1usize] - 1.0f64) + (x[3usize] - 1.0f64) * (x[3usize] - 1.0f64)) + 19.8f64 * (x[1usize] - 1.0f64) * (x[3usize] - 1.0f64)
    }
    if fid == 11usize {
        while i + 1usize < n {
            let a = x[i + 1usize] - x[i] * x[i]
            let b = 1.0f64 - x[i]
            s = s + 100.0f64 * a * a + b * b
            i += 1usize
        }
        ret s
    }
    if fid == 12usize {
        if x[0usize] < 0.0f64 - 0.5f64 { ret 0.0f64 / 0.0f64 }
        let a = x[0usize] - 1.0f64
        let b = x[1usize] - 1.0f64
        ret a * a + b * b
    }
    if fid == 13usize { ret math.exp[f64](x[0usize]) - 2.0f64 * x[0usize] + x[1usize] * x[1usize] }
    if fid == 14usize {
        let a = x[0usize]
        ret a * a * a * a - 3.0f64 * a * a + a
    }
    if fid == 15usize {
        var tot = 0.0f64
        while i < n {
            s = s + (x[i] - 0.5f64 * f64(i + 1usize)) * (x[i] - 0.5f64 * f64(i + 1usize))
            tot = tot + x[i]
            i += 1usize
        }
        ret s + 0.01f64 * tot * tot
    }
    let a = x[0usize] - 1.0f64
    ret 1.0f64 + a * a * a * a
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nlm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (out, oe) = mem.alloc[f64](a, 64usize)
    if oe != ok { os.exit(5) }
    var failures = 0usize
    var data = 0usize
    var lastfail = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var idx = 0usize
        var got = 0.0f64
        if str.eq(c.name, "o") {
            idx = usize(c.args[0usize])
            got = out[idx]
        } else {
            data += 1usize
            let n = usize(c.args[2usize])
            let (par, pe) = mem.alloc[f64](a, n)
            if pe != ok { os.exit(6) }
            var i = 0usize
            while i < n {
                par[i] = c.args[3usize + i]
                i += 1usize
            }
            let m = usize(c.args[3usize + n])
            var pr = Prob { fid: usize(c.args[0usize]), data: c.args[4usize + n..4usize + n + m] }
            var lim = 100usize
            if c.args[1usize] == c.args[1usize] { lim = usize(c.args[1usize]) }
            let r = nl.nlm[Prob](a, &pr, objective, par, lim)
            out[0usize] = r.fv
            out[1usize] = f64(r.code)
            out[2usize] = f64(r.iters)
            i = 0usize
            while i < n {
                out[3usize + i] = par[i]
                i += 1usize
            }
            got = out[0usize]
        }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 400usize && data != lastfail {
                lastfail = data
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, "case ")
                    let _ = str.push_i64(&b, i64(data))
                    let _ = str.push(&b, " idx ")
                    let _ = str.push_i64(&b, i64(idx))
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = str.push(&b, "\n")
                    let _ = io.print(str.done(&b))
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
