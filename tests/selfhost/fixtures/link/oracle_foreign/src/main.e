// e.fmt.arff and e.fmt.dbf against foreign::read.arff and read.dbf. tests/oracle/foreign.json and the files under tests/oracle/data come from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R foreign`; the layout is at the top of scripts/r_oracle/groups/foreign.R.

use e.fmt.arff as arff
use e.fmt.dbf as dbf
use e.fmt.mtp as mtp
use e.fmt.systat as systat
use e.fs
use e.io
use e.mem
use e.os
use e.str
use e.time
use e.test.oracle as oracle

fn path_of(a: *mem.Arena, stem: str, idx: usize, ext: str) -> str {
    let (b, e) = str.builder(a, 64usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push(&bb, "tests/oracle/data/foreign_")
    let _ = str.push(&bb, stem)
    if idx >= 10usize { let _ = str.push_u64(&bb, u64(idx)) } else { let _ = str.push_byte(&bb, u8(48usize + idx)) }
    let _ = str.push(&bb, ext)
    ret str.done(&bb)
}

fn utxt(a: *mem.Arena, v: usize) -> str {
    let (b, e) = str.builder(a, 24usize)
    if e != ok { os.exit(5) }
    var bb = b
    let _ = str.push_u64(&bb, u64(v))
    ret str.done(&bb)
}

fn nm_of(j: usize) -> str {
    let m = j % 6usize
    if m == 0usize { ret "V1" }
    if m == 1usize { ret "2nd" }
    if m == 2usize { ret "a b" }
    if m == 3usize { ret "x.y" }
    if m == 4usize { ret "_z" }
    ret "Q"
}

fn rl_of(i: usize) -> str {
    if i == 0usize { ret "df" }
    if i == 1usize { ret "my data" }
    if i == 2usize { ret "1abc" }
    ret "a-b"
}

fn lv_of(i: usize) -> str {
    if i == 0usize { ret "L1" }
    if i == 1usize { ret "it's" }
    if i == 2usize { ret "a\\b" }
    if i == 3usize { ret "x y" }
    if i == 4usize { ret "plain" }
    if i == 5usize { ret "Z9" }
    ret "q'r\\s"
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let idx = usize(x[0usize])
    let col = usize(x[1usize])
    let k = c.name
    if str.eq(k, "ddim") || str.eq(k, "dsum") || str.eq(k, "dnas") {
        let (bytes, re) = fs.read_file(a, path_of(a, "dbf", idx, ".dbf"), 1048576usize)
        if re != ok { os.exit(6) }
        let (t, pe) = dbf.parse(a, bytes)
        if pe != ok { os.exit(7) }
        if str.eq(k, "ddim") {
            if col == 0usize { ret f64(t.nrows) }
            ret f64(t.ncols)
        }
        var s = 0.0f64
        var n = 0.0f64
        var r = 0usize
        while r < t.nrows {
            let v = t.values[r * t.ncols + col]
            if v == v { s += v } else { n += 1.0f64 }
            r += 1usize
        }
        if str.eq(k, "dsum") { ret s }
        ret n
    }
    if str.eq(k, "dname") || str.eq(k, "dtype") || str.eq(k, "dstr") || str.eq(k, "dcode") || str.eq(k, "dnlev") || str.eq(k, "dlev") {
        let (bytes, re) = fs.read_file(a, path_of(a, "dbf", idx, ".dbf"), 1048576usize)
        if re != ok { os.exit(6) }
        let (t, pe) = dbf.parse(a, bytes)
        if pe != ok { os.exit(7) }
        if str.eq(k, "dname") {
            var ns = 0.0f64
            var q = 0usize
            while q < t.names[col].len {
                ns += f64(q + 1usize) * f64(t.names[col][q])
                q += 1usize
            }
            ret ns
        }
        if str.eq(k, "dtype") { ret f64(t.dtype[col]) }
        if str.eq(k, "dstr") {
            var acc = 0.0f64
            var r = 0usize
            while r < t.nrows {
                let tx = t.txt[r * t.ncols + col]
                var q = 0usize
                var h = 0.0f64
                while q < tx.len {
                    h += f64(q + 1usize) * f64(tx[q])
                    q += 1usize
                }
                acc += f64(r + 1usize) * h
                r += 1usize
            }
            ret acc
        }
        let (codes, levels, fe) = dbf.factor(a, t, col)
        if fe != ok { os.exit(20) }
        if str.eq(k, "dnlev") { ret f64(levels.len) }
        if str.eq(k, "dlev") {
            var ls = 0.0f64
            var lk = 0usize
            while lk < levels.len {
                var q = 0usize
                var h = 0.0f64
                while q < levels[lk].len {
                    h += f64(q + 1usize) * f64(levels[lk][q])
                    q += 1usize
                }
                ls += f64(lk + 1usize) * h
                lk += 1usize
            }
            ret ls
        }
        var cs = 0.0f64
        var r2 = 0usize
        while r2 < t.nrows {
            cs += f64(r2 + 1usize) * codes[r2]
            r2 += 1usize
        }
        ret cs
    }
    if str.eq(k, "wd") || str.eq(k, "wf") {
        // "wf" carries max_nchar and factor2char before the kinds; kind 5 is a factor, written as text "L<code>" when factor2char, else as its code
        var off = 3usize
        var mxn = 254usize
        var f2c = false
        var stem = "dbfw"
        if str.eq(k, "wf") {
            off = 5usize
            mxn = usize(x[3usize])
            f2c = x[4usize] != 0.0f64
            stem = "dbff"
        }
        let nc = usize(x[1usize])
        let nr = usize(x[2usize])
        let (kinds, e1) = mem.alloc[usize](a, nc)
        let (names, e2) = mem.alloc[str](a, nc)
        let (strv, e3) = mem.alloc[str](a, nc * nr)
        let (fac, e4) = mem.alloc[bool](a, nc)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(9) }
        let vals = x[off + nc..off + nc + nc * nr]
        var j = 0usize
        while j < nc {
            kinds[j] = usize(x[off + j])
            fac[j] = kinds[j] == 5usize && f2c
            if fac[j] { kinds[j] = 3usize }
            let (nb, ne) = str.builder(a, 16usize)
            if ne != ok { os.exit(9) }
            var nbb = nb
            let _ = str.push(&nbb, "V")
            let _ = str.push_byte(&nbb, u8(49usize + j))
            names[j] = str.done(&nbb)
            var r = 0usize
            while r < nr {
                let v = vals[j * nr + r]
                strv[j * nr + r] = ""
                if v == v && fac[j] {
                    let (sb, se) = str.builder(a, 32usize)
                    if se != ok { os.exit(9) }
                    var sbb = sb
                    let _ = str.push(&sbb, "L")
                    let _ = str.push_u64(&sbb, u64(v))
                    strv[j * nr + r] = str.done(&sbb)
                }
                if v == v && kinds[j] == 3usize && !fac[j] {
                    let (sb, se) = str.builder(a, 32usize)
                    if se != ok { os.exit(9) }
                    var sbb = sb
                    var q = 0usize
                    while q < usize(v) {
                        let _ = str.push_byte(&sbb, 97u8)
                        q += 1usize
                    }
                    strv[j * nr + r] = str.done(&sbb)
                }
                if v == v && kinds[j] == 4usize {
                    let (sb, se) = str.builder(a, 32usize)
                    if se != ok { os.exit(9) }
                    var sbb = sb
                    let _ = str.push_i64(&sbb, i64(v))
                    strv[j * nr + r] = str.done(&sbb)
                }
                r += 1usize
            }
            j += 1usize
        }
        let (out, we) = dbf.write_dbf(a, nr, nc, kinds, names, vals, strv, mxn)
        if we != ok { os.exit(61) }
        let (gold, ge) = fs.read_file(a, path_of(a, stem, idx, ".dbf"), 1048576usize)
        if ge != ok { os.exit(62) }
        if gold.len != out.len {
            let _ = io.print("LEN ")
            let _ = io.print(utxt(a, gold.len))
            let _ = io.print(" ")
            let _ = io.print(utxt(a, out.len))
            let _ = io.print("\n")
            ret 0.0f64
        }
        var bi = 0usize
        while bi < out.len {
            if (bi < 1usize || bi > 3usize) && gold[bi] != out[bi] {
                let _ = io.print(utxt(a, bi))
                let _ = io.print(" ")
                let _ = io.print(utxt(a, usize(gold[bi])))
                let _ = io.print(" ")
                let _ = io.print(utxt(a, usize(out[bi])))
                let _ = io.print("\n")
                ret 0.0f64
            }
            bi += 1usize
        }
        ret 1.0f64
    }
    if str.eq(k, "wx") || str.eq(k, "we") {
        // "we" is "wx" with an eol (files arffe): CRLF, CR, "||", LF LF
        var eol: str = "\n"
        var wstem: str = "arffv"
        if str.eq(k, "we") {
            wstem = "arffe"
            if idx == 1usize { eol = "\r\n" } else if idx == 2usize { eol = "\r" } else if idx == 3usize { eol = "||" } else { eol = "\n\n" }
        }
        let nc = usize(x[1usize])
        let nr = usize(x[2usize])
        let (kind, e1) = mem.alloc[u8](a, nc)
        let (nlev, e2) = mem.alloc[usize](a, nc)
        let (names, e3) = mem.alloc[str](a, nc)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(9) }
        var tot = 0usize
        var j = 0usize
        while j < nc {
            kind[j] = u8(x[3usize + j])
            nlev[j] = usize(x[3usize + nc + j])
            if kind[j] == 1u8 || kind[j] == 2u8 { tot += nlev[j] }
            names[j] = nm_of(j)
            j += 1usize
        }
        let (levels, e4) = mem.alloc[str](a, tot + 1usize)
        if e4 != ok { os.exit(9) }
        var li = 0usize
        j = 0usize
        while j < nc {
            if kind[j] == 1u8 || kind[j] == 2u8 {
                var l = 0usize
                while l < nlev[j] {
                    levels[li] = lv_of((l + j + 2usize) % 7usize)
                    li += 1usize
                    l += 1usize
                }
            }
            j += 1usize
        }
        let t = arff.Arff { ncols: nc, nrows: nr, kind: kind, nlev: nlev, values: x[3usize + 2usize * nc..3usize + 2usize * nc + nr * nc], lvl: levels, txt: levels }
        let (out, we) = arff.write(a, rl_of(idx % 4usize), names, levels, t, eol)
        if we != ok { os.exit(10) }
        let (gold, ge) = fs.read_file(a, path_of(a, wstem, idx, ".arff"), 1048576usize)
        if ge != ok { os.exit(11) }
        var same = out.len == gold.len
        var q = 0usize
        while same && q < out.len {
            if out[q] != gold[q] { same = false }
            q += 1usize
        }
        if !same {
            // the first line that differs, both sides
            let _ = io.print("LEN ")
            let _ = io.print(utxt(a, out.len))
            let _ = io.print("\n")
            var fl = 0usize
            var ls = 0usize
            var gs = 0usize
            var oi = 0usize
            var gi = 0usize
            var found = false
            while !found && (oi < out.len || gi < gold.len) {
                var oe = oi
                while oe < out.len && out[oe] != 10u8 { oe += 1usize }
                var ge2 = gi
                while ge2 < gold.len && gold[ge2] != 10u8 { ge2 += 1usize }
                ls = oi
                gs = gi
                if !str.eq(out[oi..oe], gold[gi..ge2]) {
                    found = true
                    let _ = io.print("wx ")
                    let _ = io.print(utxt(a, idx))
                    let _ = io.print(" line ")
                    let _ = io.print(utxt(a, fl))
                    let _ = io.print("\n")
                    let _ = io.print(out[oi..oe])
                    let _ = io.print("\n")
                    let _ = io.print(gold[gi..ge2])
                    let _ = io.print("\n")
                }
                oi = oe + 1usize
                gi = ge2 + 1usize
                fl += 1usize
            }
        }
        if same { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(k, "wr") {
        let nc = usize(x[1usize])
        let nr = usize(x[2usize])
        let (kind, e1) = mem.alloc[u8](a, nc)
        let (nlev, e2) = mem.alloc[usize](a, nc)
        let (names, e3) = mem.alloc[str](a, nc)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(9) }
        var tot = 0usize
        var j = 0usize
        while j < nc {
            kind[j] = u8(x[3usize + j])
            nlev[j] = usize(x[3usize + nc + j])
            tot += nlev[j]
            let (nb, ne) = str.builder(a, 16usize)
            if ne != ok { os.exit(9) }
            var nbb = nb
            let _ = str.push(&nbb, "V")
            let _ = str.push_byte(&nbb, u8(49usize + j))
            names[j] = str.done(&nbb)
            j += 1usize
        }
        let (levels, e4) = mem.alloc[str](a, tot + 1usize)
        if e4 != ok { os.exit(9) }
        var li = 0usize
        j = 0usize
        while j < nc {
            var l = 0usize
            while l < nlev[j] {
                let (lb, le) = str.builder(a, 8usize)
                if le != ok { os.exit(9) }
                var lbb = lb
                let _ = str.push(&lbb, "L")
                let _ = str.push_byte(&lbb, u8(49usize + l))
                levels[li] = str.done(&lbb)
                li += 1usize
                l += 1usize
            }
            j += 1usize
        }
        let t = arff.Arff { ncols: nc, nrows: nr, kind: kind, nlev: nlev, values: x[3usize + 2usize * nc..3usize + 2usize * nc + nr * nc], lvl: levels, txt: levels }
        let (out, we) = arff.write(a, "df", names, levels, t, "\n")
        if we != ok { os.exit(10) }
        let (gold, ge) = fs.read_file(a, path_of(a, "arffw", idx, ".arff"), 1048576usize)
        if ge != ok { os.exit(11) }
        var same = out.len == gold.len
        var q = 0usize
        while same && q < out.len {
            if out[q] != gold[q] { same = false }
            q += 1usize
        }
        if same { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(k, "merr") || str.eq(k, "mn") || str.eq(k, "mname") || str.eq(k, "mdim") || str.eq(k, "msum") {
        let (mb, mr) = fs.read_file(a, path_of(a, "mtp", idx, ".mtp"), 1048576usize)
        if mr != ok { os.exit(14) }
        let (mt, mp) = mtp.parse(a, mb)
        if str.eq(k, "merr") {
            if mp != ok { ret 1.0f64 }
            ret 0.0f64
        }
        if mp != ok { os.exit(15) }
        if str.eq(k, "mn") { ret f64(mt.n) }
        if str.eq(k, "mname") {
            var ns = 0.0f64
            var q = 0usize
            while q < mt.namelen[col] {
                ns += f64(q + 1usize) * f64(mt.src[mt.nameat[col] + q])
                q += 1usize
            }
            ret ns
        }
        if str.eq(k, "mdim") {
            if usize(x[2usize]) == 0usize { ret f64(mt.nrow[col]) }
            ret f64(mt.ncol[col])
        }
        var ms = 0.0f64
        var q = 0usize
        while q < mt.vals[col].len {
            ms += f64(q + 1usize) * mt.vals[col][q]
            q += 1usize
        }
        ret ms
    }
    if str.eq(k, "serr") || str.eq(k, "sn") || str.eq(k, "sname") || str.eq(k, "sstr") || str.eq(k, "snum") || str.eq(k, "snas") || str.eq(k, "slen") || str.eq(k, "shash") {
        var sp = ""
        if idx == 1usize { sp = "tests/oracle/data/foreign_iris.syd" } else if idx == 2usize { sp = "tests/oracle/data/foreign_hillrace.syd" } else {
            let (pb, pe) = str.builder(a, 80usize)
            if pe != ok { os.exit(5) }
            var pbb = pb
            let _ = str.push(&pbb, "tests/oracle/data/foreign_sys")
            let _ = str.push_u64(&pbb, u64(idx))
            let _ = str.push(&pbb, ".sys")
            sp = str.done(&pbb)
        }
        let (sb, sr) = fs.read_file(a, sp, 1048576usize)
        if sr != ok { os.exit(16) }
        var st: systat.Systat = zero
        var sperr = ok
        if x.len > 2usize && x[2usize] == 1.0f64 {
            let (st1, sp1) = systat.parse_list(a, sb)
            st = st1
            sperr = sp1
        } else {
            let (st2, sp2) = systat.parse(a, sb)
            st = st2
            sperr = sp2
        }
        if str.eq(k, "serr") {
            if sperr != ok { ret 1.0f64 }
            ret 0.0f64
        }
        if sperr != ok { os.exit(17) }
        if str.eq(k, "sn") {
            if col == 0usize { ret f64(st.nobs) }
            ret f64(st.nv)
        }
        if str.eq(k, "sname") {
            var ns = 0.0f64
            var q = 0usize
            while q < st.names[col].len {
                ns += f64(q + 1usize) * f64(st.names[col][q])
                q += 1usize
            }
            ret ns
        }
        if str.eq(k, "sstr") {
            if st.isstr[col] { ret 1.0f64 }
            ret 0.0f64
        }
        var acc = 0.0f64
        var nas = 0.0f64
        var o = 0usize
        while o < st.nobs {
            if st.isstr[col] {
                let ix = col * st.nobs + o
                if st.sna[ix] { nas += 1.0f64 } else {
                    acc += 0.0f64
                    if str.eq(k, "slen") { acc += f64(st.slen[ix]) }
                    if str.eq(k, "shash") {
                        var h = 0.0f64
                        var q = 0usize
                        while q < st.slen[ix] {
                            h += f64(q + 1usize) * f64(st.sbuf[st.sat[ix] + q])
                            q += 1usize
                        }
                        acc += f64(o + 1usize) * h
                    }
                }
            } else {
                let v = st.num[col * st.nobs + o]
                if v == v { acc += f64(o + 1usize) * v } else { nas += 1.0f64 }
            }
            o += 1usize
        }
        if str.eq(k, "snas") { ret nas }
        ret acc
    }
    if str.eq(k, "rerr") || str.eq(k, "rn") || str.eq(k, "rsum") || str.eq(k, "rnas") || str.eq(k, "rnlev") || str.eq(k, "rlev") || str.eq(k, "rstr") {
        let (rb, rr) = fs.read_file(a, path_of(a, "arffs", idx, ".arff"), 1048576usize)
        if rr != ok { os.exit(18) }
        let (rt, rp) = arff.parse(a, rb)
        if str.eq(k, "rerr") {
            if rp != ok { ret 1.0f64 }
            ret 0.0f64
        }
        if rp != ok { os.exit(19) }
        if str.eq(k, "rn") {
            if col == 0usize { ret f64(rt.nrows) }
            ret f64(rt.ncols)
        }
        if str.eq(k, "rnlev") { ret f64(rt.nlev[col]) }
        if str.eq(k, "rlev") {
            var lb = 0usize
            var cj = 0usize
            while cj < col {
                if rt.kind[cj] == 1u8 { lb += rt.nlev[cj] }
                cj += 1usize
            }
            var ls = 0.0f64
            var lk = 0usize
            while lk < rt.nlev[col] {
                let tx = rt.lvl[lb + lk]
                var lq = 0usize
                var h = 0.0f64
                while lq < tx.len {
                    h += f64(lq + 1usize) * f64(tx[lq])
                    lq += 1usize
                }
                ls += f64(lk + 1usize) * h
                lk += 1usize
            }
            ret ls
        }
        var racc = 0.0f64
        var rnas = 0.0f64
        var ro = 0usize
        while ro < rt.nrows {
            let rv = rt.values[ro * rt.ncols + col]
            if rv == rv {
                if str.eq(k, "rstr") {
                    let tx = rt.txt[ro * rt.ncols + col]
                    var lq = 0usize
                    var h = 0.0f64
                    while lq < tx.len {
                        h += f64(lq + 1usize) * f64(tx[lq])
                        lq += 1usize
                    }
                    racc += f64(ro + 1usize) * h
                } else {
                    racc += f64(ro + 1usize) * rv
                }
            } else {
                rnas += 1.0f64
            }
            ro += 1usize
        }
        if str.eq(k, "rnas") { ret rnas }
        ret racc
    }
    if str.starts_with(k, "x") {
        let (xt, xr) = fs.read_file(a, path_of(a, "arffx", idx, ".arff"), 1048576usize)
        if xr != ok { os.exit(12) }
        var xtoday = 0i64
        if str.eq(k, "xfull") { xtoday = i64(x[2usize]) }
        let (xa, xp) = arff.parse_on(a, xt, xtoday)
        if xp != ok { os.exit(13) }
        var xs = 0.0f64
        var xn = 0.0f64
        var xr2 = 0usize
        while xr2 < xa.nrows {
            let v = xa.values[xr2 * xa.ncols + col]
            if v == v {
                let days = time.floor_div(i64(v), 86400i64)
                let (cy, cm, cd) = time.civil_from_days(days)
                if str.eq(k, "xtod") { xs += v - f64(days * 86400i64) }
                if str.eq(k, "xfull") { xs += f64(xr2 + 1usize) * v }
                if str.eq(k, "xyr") { xs += f64(cy) }
                if str.eq(k, "xdom") { xs += f64(cd) }
                if str.eq(k, "xmd") { xs += f64(cm * 100i64 + cd) }
            } else {
                xn += 1.0f64
            }
            xr2 += 1usize
        }
        if str.eq(k, "xnas") { ret xn }
        ret xs
    }
    let (text, re) = fs.read_file(a, path_of(a, "arff", idx, ".arff"), 1048576usize)
    if re != ok { os.exit(8) }
    let (t, pe) = arff.parse(a, text)
    if str.eq(k, "aerr") {
        if pe != ok { ret 1.0f64 }
        ret 0.0f64
    }
    if pe != ok { os.exit(9) }
    if str.eq(k, "dim") {
        if col == 0usize { ret f64(t.nrows) }
        ret f64(t.ncols)
    }
    var s = 0.0f64
    var n = 0.0f64
    var r = 0usize
    while r < t.nrows {
        let v = t.values[r * t.ncols + col]
        if v == v { s += v } else { n += 1.0f64 }
        r += 1usize
    }
    if str.eq(k, "sum") { ret s }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/foreign.json")
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
