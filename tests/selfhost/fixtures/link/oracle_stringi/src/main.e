// e.text.normalize against stringi. tests/oracle/stringi.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R stringi`; the layout is at the top of scripts/r_oracle/groups/stringi.R.

use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle
use e.text.charset as cs
use e.text.normalize as nz
use e.text.segment as sg
use e.text.unicode as uc

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "enc") {
        var enames: [12]str = zero
        enames[0usize] = "windows-1252"
        enames[1usize] = "windows-1251"
        enames[2usize] = "windows-1250"
        enames[3usize] = "windows-1253"
        enames[4usize] = "windows-1254"
        enames[5usize] = "windows-1257"
        enames[6usize] = "ISO-8859-2"
        enames[7usize] = "ISO-8859-5"
        enames[8usize] = "ISO-8859-7"
        enames[9usize] = "ISO-8859-15"
        enames[10usize] = "KOI8-R"
        enames[11usize] = "macintosh"
        var ebuf: [4]u8 = zero
        let ew = uc.write_utf8(u32(x[1usize]), ebuf[0usize..4usize], 0usize)
        let (en, eok) = cs.label_to_name(enames[usize(x[0usize])])
        if !eok { os.exit(11) }
        let idx = cs.single_index(en)
        var subb = 26u8
        if usize(x[0usize]) == 11usize { subb = 63u8 }
        let (bytes, ee) = cs.encode_single(a, idx, ebuf[0usize..ew], subb)
        if ee != ok || bytes.len != 1usize { os.exit(12) }
        ret f64(bytes[0usize])
    }
    if str.eq(c.name, "dec") {
        var names: [12]str = zero
        names[0usize] = "windows-1252"
        names[1usize] = "windows-1251"
        names[2usize] = "windows-1250"
        names[3usize] = "windows-1253"
        names[4usize] = "windows-1254"
        names[5usize] = "windows-1257"
        names[6usize] = "ISO-8859-2"
        names[7usize] = "ISO-8859-5"
        names[8usize] = "ISO-8859-7"
        names[9usize] = "ISO-8859-15"
        names[10usize] = "KOI8-R"
        names[11usize] = "macintosh"
        let (cn, ok1) = cs.label_to_name(names[usize(x[0usize])])
        if !ok1 { os.exit(9) }
        var bb: [1]u8 = zero
        bb[0usize] = u8(x[1usize])
        let (txt, de) = cs.decode(a, cn, bb[0usize..1usize])
        if de != ok { os.exit(10) }
        let (sc, adv) = uc.read_utf8(txt, 0usize)
        let _ = adv
        ret f64(sc)
    }
    if str.eq(c.name, "case") {
        if usize(x[1usize]) == 0usize { ret f64(uc.to_lower_simple(u32(x[0usize]))) }
        ret f64(uc.to_upper_simple(u32(x[0usize])))
    }
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
    if str.eq(c.name, "hex") {
        let (hx, he) = uc.any_hex(a, s, usize(x[1usize + n]))
        if he != ok { os.exit(13) }
        if usize(x[2usize + n]) == 0usize { ret f64(hx.len) }
        var hs = 0.0f64
        var q3 = 0usize
        while q3 < hx.len {
            hs += f64(hx[q3]) * f64(q3 + 1usize)
            q3 += 1usize
        }
        ret hs
    }
    if str.eq(c.name, "lc") {
        var cv = ""
        if usize(x[1usize + n]) == 0usize {
            let (lw, le) = uc.to_lower(a, s)
            if le != ok { os.exit(14) }
            cv = lw
        } else {
            let (up, ue) = uc.to_upper(a, s)
            if ue != ok { os.exit(15) }
            cv = up
        }
        var cnt2 = 0usize
        var sum2 = 0.0f64
        var at2 = 0usize
        while at2 < cv.len {
            let (sc2, adv2) = uc.read_utf8(cv, at2)
            cnt2 += 1usize
            sum2 += f64(sc2) * f64(cnt2)
            at2 += adv2
        }
        if usize(x[2usize + n]) == 0usize { ret f64(cnt2) }
        ret sum2
    }
    if str.eq(c.name, "la") {
        let (la, lae) = uc.latin_ascii(a, s)
        if lae != ok { os.exit(16) }
        var cnt3 = 0usize
        var sum3 = 0.0f64
        var at3 = 0usize
        while at3 < la.len {
            let (sc3, adv3) = uc.read_utf8(la, at3)
            cnt3 += 1usize
            sum3 += f64(sc3) * f64(cnt3)
            at3 += adv3
        }
        if usize(x[1usize + n]) == 0usize { ret f64(cnt3) }
        ret sum3
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
