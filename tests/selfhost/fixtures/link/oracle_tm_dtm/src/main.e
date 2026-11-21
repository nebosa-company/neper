// e.algo.stat.tmdtm against tm DocumentTermMatrix / TermDocumentMatrix / weightBin and tidytext unnest_tokens (sentences, regex). tests/oracle/tm_dtm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tm_dtm`; the layout is at the top of scripts/r_oracle/groups/tm_dtm.R.

use e.algo.stat.tmdtm as td
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn codes(a: *mem.Arena, z: []const f64, from: usize) -> (str, err) {
    let (bld, eb) = str.builder(a, z.len + 1usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var i = from
    while i < z.len {
        if str.push_byte(&bd, u8(z[i])) != ok { ret ("", mem.Full) }
        i += 1usize
    }
    ret (str.done(&bd), ok)
}

fn wsum(s: str) -> f64 {
    var sm = 0.0f64
    var k = 0usize
    while k < s.len {
        sm += f64(s[k]) * f64(k + 1usize)
        k += 1usize
    }
    ret sm
}

fn pattern_at(i: usize) -> str {
    if i == 0usize { ret "\\s+" }
    if i == 1usize { ret "," }
    if i == 2usize { ret "[,;]\\s*" }
    if i == 3usize { ret "\\W+" }
    if i == 4usize { ret "[^a-z]+" }
    if i == 5usize { ret "\\s*[.!?]\\s*" }
    if i == 6usize { ret "a|bb" }
    ret "[0-9]+"
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    if str.eq(c.name, "sn") || str.eq(c.name, "ss") {
        let (t, et) = codes(a, z, 0usize)
        if et != ok { ret nan }
        let (r, er) = td.tokenize_sentences(a, t)
        if er != ok { ret nan }
        if str.eq(c.name, "sn") { ret f64(r.len) }
        ret wsum(r)
    }
    if str.eq(c.name, "rn") || str.eq(c.name, "rs") {
        let (t, et) = codes(a, z, 1usize)
        if et != ok { ret nan }
        let (r, er) = td.tokenize_regex(a, t, pattern_at(usize(z[0usize])))
        if er != ok { ret nan }
        if str.eq(c.name, "rn") { ret f64(r.len) }
        ret wsum(r)
    }
    let (t, et) = codes(a, z, 9usize)
    if et != ok { ret nan }
    let (ops, eo) = mem.alloc[u8](a, 4usize)
    if eo != ok { ret nan }
    var no = 0usize
    var q = 0usize
    while q < 4usize {
        if z[5usize + q] != 0.0f64 {
            ops[no] = u8(z[5usize + q])
            no += 1usize
        }
        q += 1usize
    }
    let (d, ed) = td.dtm_build(a, t, z[0usize] != 0.0f64, ops[..no], usize(z[1usize]), usize(z[2usize]), z[3usize], z[4usize])
    if ed != ok { ret nan }
    if str.eq(c.name, "dnt") { ret f64(d.nt) }
    var tot = 0.0f64
    var ws = 0.0f64
    var wt = 0.0f64
    var wb = 0.0f64
    var hv = 0.0f64
    var r = 0usize
    while r < d.nd {
        var k = 0usize
        while k < d.nt {
            let v = d.counts[r * d.nt + k]
            tot += v
            ws += v * f64(r * d.nt + k + 1usize)
            wt += v * f64(k * d.nd + r + 1usize)
            if v != 0.0f64 { wb += f64(r * d.nt + k + 1usize) }
            hv += v * f64(r + 1usize) * wsum(d.terms[k])
            k += 1usize
        }
        r += 1usize
    }
    if str.eq(c.name, "dtot") { ret tot }
    if str.eq(c.name, "dhash") { ret hv }
    if str.eq(c.name, "dpos") { ret ws }
    if str.eq(c.name, "dtpos") { ret wt }
    ret wb
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tm_dtm.json")
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
                let (db, edb) = str.builder(a, 200usize)
                if edb == ok {
                    var dbd = db
                    let _ = str.push(&dbd, c.name)
                    let _ = str.push(&dbd, " got ")
                    let _ = str.push_f64(&dbd, got)
                    let _ = str.push(&dbd, " want ")
                    let _ = str.push_f64(&dbd, c.want)
                    let _ = str.push(&dbd, " case ")
                    let _ = str.push_usize(&dbd, at)
                    let _ = io.print(str.done(&dbd))
                    let _ = io.print("\n")
                }
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
