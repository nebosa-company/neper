// R cluster (Maechler et al., 2.1.8.2): mona, monothetic analysis of binary data, ported from the package's mona.c and the
// recoding of mona.R.
//
//   mona_recode   the two levels of each column become 0 and 1 (the sorted order of the values), NaN becomes 2
//   mona_core     the missing values filled from the most associated variable, then the divisive splits on the variable with the
//                 largest association: the order, the pass at which each object was split off, the variable used
//
// x is n by p row-major with the codes 0, 1 and 2 (missing). jerr 0 is a clustering; 1 an object with every value missing, 2 a
// variable with at least half of its values missing, 3 a variable whose observed values are all identical, 4 every variable having
// a missing value, 5 fewer than two variables.
//
// Not here: the print and summary methods.

use e.mem

type MonaOut = struct { jerr: usize, x: []usize, nban: []usize, ner: []usize, lava: []usize }

// the codes of mona.R: 0 and 1 for the lower and the higher value of a column, 2 for NaN; the answer is 1 when a column has other than
// two distinct values
fn mona_recode(xin: []const f64, n: usize, p: usize, out: []usize) -> usize {
    var j = 0usize
    while j < p {
        var lo = 0.0f64
        var hi = 0.0f64
        var have = 0usize
        var i = 0usize
        while i < n {
            let v = xin[i * p + j]
            if v == v {
                if have == 0usize {
                    lo = v
                    hi = v
                    have = 1usize
                } else {
                    if v < lo { lo = v }
                    if v > hi { hi = v }
                }
            }
            i += 1usize
        }
        if have == 0usize || lo == hi { ret 1usize }
        i = 0usize
        while i < n {
            let v = xin[i * p + j]
            if v != v {
                out[i * p + j] = 2usize
            } else {
                if v == lo {
                    out[i * p + j] = 0usize
                } else {
                    if v == hi {
                        out[i * p + j] = 1usize
                    } else {
                        ret 1usize
                    }
                }
            }
            i += 1usize
        }
        j += 1usize
    }
    ret 0usize
}

fn iabs_i(v: i64) -> i64 {
    if v >= 0i64 { ret v }
    ret 0i64 - v
}

fn mona_core(a: *mem.Arena, xin: []const usize, nn: usize, pp: usize) -> (MonaOut, err) {
    let (x, e1) = mem.alloc[usize](a, nn * pp)
    if e1 != ok { ret (zero, e1) }
    let (nban, e2) = mem.alloc[usize](a, nn + 1usize)
    if e2 != ok { ret (zero, e2) }
    let (ner, e3) = mem.alloc[usize](a, nn + 1usize)
    if e3 != ok { ret (zero, e3) }
    let (lava, e4) = mem.alloc[usize](a, nn + 1usize)
    if e4 != ok { ret (zero, e4) }
    let (kwan, e5) = mem.alloc[i64](a, nn + 1usize)
    if e5 != ok { ret (zero, e5) }
    let (jlack, e6) = mem.alloc[usize](a, pp + 1usize)
    if e6 != ok { ret (zero, e6) }
    var i = 0usize
    while i < nn * pp {
        x[i] = xin[i]
        i += 1usize
    }
    i = 0usize
    while i <= nn {
        nban[i] = 0usize
        ner[i] = 0usize
        lava[i] = 0usize
        kwan[i] = 0i64
        i += 1usize
    }
    i = 0usize
    while i <= pp {
        jlack[i] = 0usize
        i += 1usize
    }
    if pp < 2usize {
        ret (MonaOut { jerr: 5usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
    }
    let nhalf = (nn + 1usize) / 2usize
    var has_na = false
    var l = 1usize
    while l <= nn && !has_na {
        var n_miss = 0usize
        var j = 1usize
        while j <= pp {
            if x[(l - 1usize) * pp + (j - 1usize)] > 1usize { n_miss += 1usize }
            j += 1usize
        }
        if n_miss == pp {
            ret (MonaOut { jerr: 1usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
        }
        if n_miss > 0usize { has_na = true }
        l += 1usize
    }
    var jma = 0usize
    var jtel = 0usize
    var jtelz = 0usize
    var lama = 0i64
    if has_na {
        var lack = 0usize
        var j = 1usize
        while j <= pp {
            var j0 = 0usize
            var j1 = 0usize
            l = 1usize
            while l <= nn {
                let v = x[(l - 1usize) * pp + (j - 1usize)]
                if v == 0usize {
                    j0 += 1usize
                } else {
                    if v == 1usize { j1 += 1usize }
                }
                l += 1usize
            }
            jlack[j] = nn - j0 - j1
            if jlack[j] != 0usize { lack += 1usize }
            if jlack[j] >= nhalf {
                ret (MonaOut { jerr: 2usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
            }
            if j0 == 0usize || j1 == 0usize {
                ret (MonaOut { jerr: 3usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
            }
            j += 1usize
        }
        if lack == pp {
            ret (MonaOut { jerr: 4usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
        }
        j = 1usize
        while j <= pp {
            if jlack[j] != 0usize {
                lama = 0i64 - 1i64
                var syn = true
                var ja = 1usize
                while ja <= pp {
                    if jlack[ja] == 0usize {
                        var ca = 0i64
                        var cb = 0i64
                        var cc = 0i64
                        var cdd = 0i64
                        var k = 1usize
                        while k <= nn {
                            let xkj = x[(k - 1usize) * pp + (j - 1usize)]
                            let xka = x[(k - 1usize) * pp + (ja - 1usize)]
                            if xkj != 1usize {
                                if xka == 0usize {
                                    ca += 1i64
                                } else {
                                    if xka == 1usize { cb += 1i64 }
                                }
                            } else {
                                if xka == 0usize {
                                    cc += 1i64
                                } else {
                                    if xka == 1usize { cdd += 1i64 }
                                }
                            }
                            k += 1usize
                        }
                        let kal = ca * cdd - cb * cc
                        let kalf = iabs_i(kal)
                        if kalf >= lama {
                            lama = kalf
                            jma = ja
                            if kal < 0i64 { syn = false }
                        }
                    }
                    ja += 1usize
                }
                var k = 1usize
                while k <= nn {
                    if x[(k - 1usize) * pp + (j - 1usize)] > 1usize {
                        let xm = x[(k - 1usize) * pp + (jma - 1usize)]
                        if syn {
                            x[(k - 1usize) * pp + (j - 1usize)] = xm
                        } else {
                            if xm == 1usize { x[(k - 1usize) * pp + (j - 1usize)] = 0usize }
                            if xm == 0usize { x[(k - 1usize) * pp + (j - 1usize)] = 1usize }
                        }
                    }
                    k += 1usize
                }
            }
            j += 1usize
        }
    }
    // initialisation and the divisive passes
    var k = 1usize
    while k <= nn {
        kwan[k] = 0i64
        ner[k] = k
        lava[k] = 0usize
        k += 1usize
    }
    var npass = 1usize
    kwan[1usize] = i64(nn)
    var nclu = 1usize
    var ka = 1usize
    var run = true
    while run {
        let kb = ka + usize(kwan[ka]) - 1usize
        lama = 0i64 - 1i64
        var jnat = pp
        var j = 1usize
        while j <= pp {
            var consider = false
            if nclu == 1usize {
                consider = true
            } else {
                var j0 = 0usize
                var j1 = 0usize
                k = ka
                while k <= kb {
                    let v = x[(ner[k] - 1usize) * pp + (j - 1usize)]
                    if v == 0usize {
                        j0 += 1usize
                    } else {
                        if v == 1usize { j1 += 1usize }
                    }
                    k += 1usize
                }
                consider = j1 != 0usize && j0 != 0usize
            }
            if consider {
                jnat -= 1usize
                var ca = 0i64
                var cb = 0i64
                var cc = 0i64
                var cdd = 0i64
                var lams = 0i64
                var jb = 1usize
                while jb <= pp {
                    if jb != j {
                        ca = 0i64
                        cb = 0i64
                        cc = 0i64
                        cdd = 0i64
                        k = ka
                        while k <= kb {
                            let n_k = ner[k]
                            let xj = x[(n_k - 1usize) * pp + (j - 1usize)]
                            let xb = x[(n_k - 1usize) * pp + (jb - 1usize)]
                            if xj == 0usize {
                                if xb == 0usize {
                                    ca += 1i64
                                } else {
                                    if xb == 1usize { cb += 1i64 }
                                }
                            } else {
                                if xb == 0usize {
                                    cc += 1i64
                                } else {
                                    if xb == 1usize { cdd += 1i64 }
                                }
                            }
                            k += 1usize
                        }
                        lams += iabs_i(ca * cdd - cb * cc)
                    }
                    jb += 1usize
                }
                if lama < lams {
                    lama = lams
                    jtel = usize(cc + cdd)
                    jtelz = usize(ca + cb)
                    jma = j
                }
            }
            j += 1usize
        }
        if jnat < pp {
            // splitting
            let nel = ner[ka]
            var nzf = 0usize
            var jtel2 = 0usize
            if x[(nel - 1usize) * pp + (jma - 1usize)] == 1usize {
                nzf = 0usize
                jtel2 = jtel
            } else {
                nzf = 1usize
                jtel2 = jtelz
            }
            let jres = kb - ka + 1usize - jtel2
            let km = ka + jtel2
            k = ka
            var n_b = 0usize
            var inner = true
            while inner {
                let n_k = ner[k]
                if x[(n_k - 1usize) * pp + (jma - 1usize)] == nzf {
                    var c = 0usize
                    var b = k
                    var found = false
                    while b <= kb && !found {
                        n_b = ner[b]
                        if x[(n_b - 1usize) * pp + (jma - 1usize)] != nzf {
                            c = b - 1usize
                            found = true
                        }
                        b += 1usize
                    }
                    var aa = k
                    while aa <= c {
                        let d = c + k - aa
                        ner[d + 1usize] = ner[d]
                        aa += 1usize
                    }
                    ner[k] = n_b
                } else {
                    k += 1usize
                }
                if !(k < km) { inner = false }
            }
            nclu += 1usize
            nban[km] = npass
            kwan[ka] = i64(jtel2)
            kwan[km] = i64(jres)
            lava[km] = jma
            ka += jtel2
        } else {
            kwan[ka] = 0i64 - kwan[ka]
        }
        var to_pass = false
        if kb == nn {
            to_pass = true
        } else {
            var scanning = true
            while scanning {
                ka += usize(iabs_i(kwan[ka]))
                if ka > nn {
                    to_pass = true
                    scanning = false
                } else {
                    if kwan[ka] >= 2i64 { scanning = false }
                }
            }
        }
        if to_pass {
            npass += 1usize
            var found = false
            ka = 1usize
            while ka <= nn && !found {
                if kwan[ka] >= 2i64 {
                    found = true
                } else {
                    ka += 1usize
                }
            }
            if !found { run = false }
        }
    }
    ret (MonaOut { jerr: 0usize, x: x, nban: nban, ner: ner, lava: lava }, ok)
}
