// e.text.normalize against stringi. tests/oracle/stringi.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R stringi`; the layout is at the top of scripts/r_oracle/groups/stringi.R.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.normalize as nz
use e.text.segment as sg
use e.text.unicode as uc

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let (b0, e0) = str.builder(a, 64usize)
    if e0 != ok { os.exit(5) }
    var b = b0
    var i = 0usize
    while i < n {
        let sc = u32(x[1usize + i])
        var buf: [4]u8 = zero
        let w = uc.write_utf8(sc, buf[0usize..4usize], 0usize)
        var q = 0usize
        while q < w {
            let _ = str.push_byte(&b, buf[q])
            q += 1usize
        }
        i += 1usize
    }
    let s = str.done(&b)
    if str.eq(c.name, "seg") && usize(x[1usize + n]) == 1usize {
        let (cps, ce) = mem.alloc[u32](a, n)
        let (bd, be) = mem.alloc[usize](a, n + 2usize)
        if ce != ok || be != ok { os.exit(7) }
        var q2 = 0usize
        while q2 < n {
            cps[q2] = u32(x[1usize + q2])
            q2 += 1usize
        }
        let (nb, we) = sg.words(cps, bd)
        if we != ok { os.exit(8) }
        ret f64(nb - 1usize)
    }
    if str.eq(c.name, "seg") {
        var it = uc.graphemes(s)
        var gc = 0usize
        while true {
            let (g, more) = uc.graphemes_next(&it)
            if !more { break }
            let _ = g
            gc += 1usize
        }
        ret f64(gc)
    }
    let f = usize(x[1usize + n])
    var form = nz.Form.Nfc
    if f == 1usize { form = nz.Form.Nfd }
    if f == 2usize { form = nz.Form.Nfkc }
    if f == 3usize { form = nz.Form.Nfkd }
    let (out, ne) = nz.normalize(a, s, form)
    if ne != ok { os.exit(6) }
    var cnt = 0usize
    var sum = 0.0f64
    var at = 0usize
    while at < out.len {
        let (sc, adv) = uc.read_utf8(out, at)
        cnt += 1usize
        sum += f64(sc) * f64(cnt)
        at += adv
    }
    if usize(x[2usize + n]) == 0usize { ret f64(cnt) }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/stringi.json")
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
