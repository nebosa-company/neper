// e.algo.stat.mclustda against mclust. tests/oracle/mclust6.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mclust6`; the layout is at the top of scripts/r_oracle/groups/mclust6.R.
// Consecutive cases share the data, so the fit is computed once per group of cases.

use e.algo.stat.mclustda as mda
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 1usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn pick(res: []const f64, z: []const f64) -> f64 {
    let id = usize(z[0usize])
    let nclass = usize(z[4usize])
    let nn_at = 7usize + usize(z[6usize])
    let nn = usize(z[nn_at])
    if id < 4usize { ret res[id] }
    var s = 0.0f64
    var c = 0usize
    if id == 4usize {
        while c < nclass {
            s += f64(c + 1usize) * res[4usize + c]
            c += 1usize
        }
        ret s
    }
    if id == 5usize {
        while c < nclass {
            s += f64(c + 1usize) * res[4usize + nclass + c]
            c += 1usize
        }
        ret s
    }
    let off_z = 4usize + 2usize * nclass
    if id == 6usize {
        var q = 0usize
        while q < nn * nclass {
            s += f64(q + 1usize) * res[off_z + q]
            q += 1usize
        }
        ret s
    }
    var q = 0usize
    while q < nn {
        s += f64(q + 1usize) * res[off_z + nn * nclass + q]
        q += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mclust6.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (res, re) = mem.alloc[f64](a, 4000usize)
    let (key, ke) = mem.alloc[f64](a, 4000usize)
    if re != ok || ke != ok { os.exit(4) }
    var have = false
    var key_len = 0usize
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        var got = 0.0f64 / 0.0f64
        if !(have && key_len == z.len && same_key(key[0usize..key_len], z)) {
            have = false
            let typ = usize(z[1usize])
            let n = usize(z[2usize])
            let d = usize(z[3usize])
            let nclass = usize(z[4usize])
            let gmax = usize(z[5usize])
            let nm = usize(z[6usize])
            let nn = usize(z[7usize + nm])
            let (mods, me) = mem.alloc[usize](a, nm)
            let (cls, ce) = mem.alloc[usize](a, n)
            if me == ok && ce == ok {
                var q = 0usize
                while q < nm {
                    mods[q] = usize(z[7usize + q])
                    q += 1usize
                }
                var base = 8usize + nm
                q = 0usize
                while q < n {
                    cls[q] = usize(z[base + q])
                    q += 1usize
                }
                base += n
                let x = z[base..base + n * d]
                let xn = z[base + n * d..base + n * d + nn * d]
                let fe = mda.mclustda_run(a, x, n, d, cls, nclass, typ == 1usize, gmax, mods, xn, nn, res)
                if fe == ok {
                    have = true
                    key_len = z.len
                    q = 0usize
                    while q < z.len {
                        key[q] = z[q]
                        q += 1usize
                    }
                }
            }
        }
        if have { got = pick(res, z) }
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let (initial, be) = str.builder(a, 120usize)
                var b = initial
                let _ = str.push(&b, "mda id ")
                let _ = str.push_f64(&b, z[0usize])
                let _ = str.push(&b, " type ")
                let _ = str.push_f64(&b, z[1usize])
                let _ = str.push(&b, ": got ")
                let _ = str.push_f64(&b, got)
                let _ = str.push(&b, ", R says ")
                let _ = str.push_f64(&b, c.want)
                let _ = io.print(str.done(&b))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
