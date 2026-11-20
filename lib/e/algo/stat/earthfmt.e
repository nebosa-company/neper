// R earth: format.earth, the text of a model's basis functions and coefficients, one string per response (styles h, pmax, max and bf), and the glm
// coefficients' text the same way. The numbers are written the way R writes them: C's %g, and format(x, digits) with its common fixed or scientific
// layout, both from the exact decimal expansion of the double.
//
// Not here: style C, make.unique of duplicate term names, and the factor simplification of h(x-0).

use e.algo.stat.earthfit as ef
use e.math
use e.mem

// ---- exact decimal digits

type Dec = struct { d: [1200]u8, used: usize, exp: i64 }

// v > 0 finite: v = 0.d0d1d2... * 10^exp, exactly
fn exact_dec(v: f64) -> Dec {
    var r: Dec = zero
    let bits = mem.bitcast[u64](v)
    let ef_ = bits >> 52u64 & 2047u64
    let mf = bits & 4503599627370495u64
    var scale = mf
    var power = 0i64
    if ef_ == 0u64 {
        power = -1074i64
    } else {
        scale = mf + 4503599627370496u64
        power = i64(ef_) - 1075i64
    }
    var used = 0usize
    var exponent = 0i64
    if scale != 0u64 {
        var rev: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u64 {
            rev[length] = u8(rest % 10u64)
            length += 1usize
            rest = rest / 10u64
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            r.d[back] = rev[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && r.d[used - 1usize] == 0u8 { used = used - 1usize }
    }
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = r.d[scan] * 2u8 + carry
                r.d[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    r.d[shift] = r.d[shift - 1usize]
                }
                r.d[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + r.d[scan]
                r.d[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                r.d[used] = 5u8
                used += 1usize
            }
            if r.d[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    r.d[shift] = r.d[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && r.d[used - 1usize] == 0u8 { used = used - 1usize }
    }
    r.used = used
    r.exp = exponent
    ret r
}

// p significant digits (p >= 1, at most 40): value = d0.d1d2... * 10^e10, a tie rounding to even
type Sig = struct { d: [40]u8, e10: i64 }

fn round_sig(x: *const Dec, p: usize) -> Sig {
    var s: Sig = zero
    if x.used == 0usize { ret s }
    var k = 0usize
    while k < p {
        if k < x.used { s.d[k] = x.d[k] }
        k += 1usize
    }
    var next = 0u8
    if p < x.used { next = x.d[p] }
    var more = false
    var q = p + 1usize
    while q < x.used {
        if x.d[q] != 0u8 { more = true }
        q += 1usize
    }
    var up = false
    if next > 5u8 { up = true }
    if next == 5u8 {
        if more || s.d[p - 1usize] % 2u8 == 1u8 { up = true }
    }
    s.e10 = x.exp - 1i64
    if up {
        var at = p
        var carry = true
        while carry && at > 0usize {
            at = at - 1usize
            if s.d[at] == 9u8 {
                s.d[at] = 0u8
            } else {
                s.d[at] += 1u8
                carry = false
            }
        }
        if carry {
            s.d[0usize] = 1u8
            s.e10 += 1i64
        }
    }
    ret s
}

// ---- writer

type W = struct { b: []u8, n: usize }

fn put(w: *W, c: u8) {
    w.b[w.n] = c
    w.n += 1usize
}

fn put_str(w: *W, s: []const u8, n: usize) {
    var i = 0usize
    while i < n {
        put(w, s[i])
        i += 1usize
    }
}

fn put_lit(w: *W, s: str) {
    var i = 0usize
    while i < s.len {
        put(w, s[i])
        i += 1usize
    }
}

fn put_uint(w: *W, v: i64) {
    var t: [24]u8 = zero
    var n = 0usize
    var r = v
    if r == 0i64 {
        put(w, 48u8)
        ret
    }
    while r > 0i64 {
        t[n] = u8(48i64 + r % 10i64)
        r = r / 10i64
        n += 1usize
    }
    while n > 0usize {
        n -= 1usize
        put(w, t[n])
    }
}

fn pad(w: *W, n: usize) {
    var i = 0usize
    while i < n {
        put(w, 32u8)
        i += 1usize
    }
}

// the digit of s at index i, zero beyond the p digits it has
fn dig(s: *const Sig, p: usize, i: i64) -> u8 {
    if i < 0i64 || usize(i) >= p { ret 48u8 }
    ret 48u8 + s.d[usize(i)]
}

// C's %.{rgt}f of v >= 0
fn put_fixed(w: *W, v: f64, rgt: usize) {
    var s: Sig = zero
    var e10 = 0i64
    var p = 1usize
    var zero_v = v == 0.0f64
    if !zero_v {
        let dc = exact_dec(v)
        let pp = dc.exp - 1i64 + 1i64 + i64(rgt)
        if pp >= 1i64 {
            p = usize(pp)
            s = round_sig(&dc, p)
            e10 = s.e10
        } else {
            // the value lies below one unit of the last place: it rounds to zero or to one unit
            var up = false
            if pp == 0i64 {
                if dc.d[0usize] > 5u8 { up = true }
                if dc.d[0usize] == 5u8 {
                    var q = 1usize
                    while q < dc.used {
                        if dc.d[q] != 0u8 { up = true }
                        q += 1usize
                    }
                }
            }
            if up {
                s.d[0usize] = 1u8
                e10 = dc.exp
                p = 1usize
            } else {
                zero_v = true
            }
        }
    }
    if zero_v {
        put(w, 48u8)
        if rgt > 0usize {
            put(w, 46u8)
            pad_zero(w, rgt)
        }
        ret
    }
    if e10 >= 0i64 {
        var i = 0i64
        while i <= e10 {
            put(w, dig(&s, p, i))
            i += 1i64
        }
    } else {
        put(w, 48u8)
    }
    if rgt > 0usize {
        put(w, 46u8)
        var k = 1i64
        while k <= i64(rgt) {
            put(w, dig(&s, p, e10 + k))
            k += 1i64
        }
    }
}

fn pad_zero(w: *W, n: usize) {
    var i = 0usize
    while i < n {
        put(w, 48u8)
        i += 1usize
    }
}

fn put_exp(w: *W, x: i64) {
    put(w, 101u8)
    var ax = x
    if x < 0i64 {
        put(w, 45u8)
        ax = 0i64 - x
    } else {
        put(w, 43u8)
    }
    if ax < 10i64 { put(w, 48u8) }
    put_uint(w, ax)
}

// C's %.{d}e of v >= 0
fn put_sci(w: *W, v: f64, d: usize) {
    var s: Sig = zero
    if v != 0.0f64 {
        let dc = exact_dec(v)
        s = round_sig(&dc, d + 1usize)
    }
    put(w, 48u8 + s.d[0usize])
    if d > 0usize {
        put(w, 46u8)
        var k = 1usize
        while k <= d {
            put(w, 48u8 + s.d[k])
            k += 1usize
        }
    }
    put_exp(w, s.e10)
}

// C's %.{p}g of v, trailing zeros dropped
fn put_g(w: *W, v: f64, p_in: usize) {
    var p = p_in
    if p == 0usize { p = 1usize }
    if v == 0.0f64 {
        put(w, 48u8)
        ret
    }
    var av = v
    if v < 0.0f64 {
        put(w, 45u8)
        av = 0.0f64 - v
    }
    let dc = exact_dec(av)
    let s = round_sig(&dc, p)
    var nd = p
    while nd > 1usize && s.d[nd - 1usize] == 0u8 { nd -= 1usize }
    let x = s.e10
    if x >= -4i64 && x < i64(p) {
        if x >= 0i64 {
            var i = 0i64
            while i <= x {
                put(w, dig(&s, p, i))
                i += 1i64
            }
            if i64(nd) > x + 1i64 {
                put(w, 46u8)
                var k = x + 1i64
                while k < i64(nd) {
                    put(w, dig(&s, p, k))
                    k += 1i64
                }
            }
        } else {
            put(w, 48u8)
            put(w, 46u8)
            var z = 0i64
            while z < 0i64 - x - 1i64 {
                put(w, 48u8)
                z += 1i64
            }
            var k = 0usize
            while k < nd {
                put(w, 48u8 + s.d[k])
                k += 1usize
            }
        }
    } else {
        put(w, 48u8 + s.d[0usize])
        if nd > 1usize {
            put(w, 46u8)
            var k = 1usize
            while k < nd {
                put(w, 48u8 + s.d[k])
                k += 1usize
            }
        }
        put_exp(w, x)
    }
}

// ---- R's format(x, digits) of a numeric vector: formatReal

type Fmt = struct { fixed: bool, w: usize, d: usize }

fn real_info(vals: []const f64, digits: usize) -> Fmt {
    var f: Fmt = zero
    var neg = false
    var mxsl = 1i64
    var mxrgt = 0i64
    var mxe = -1000i64
    var mne = 1000i64
    var mxns = 0i64
    var any = false
    var i = 0usize
    while i < vals.len {
        let v = vals[i]
        var av = v
        var isneg = false
        if v < 0.0f64 {
            isneg = true
            av = 0.0f64 - v
        }
        var kp = 0i64
        var nsig = 1i64
        if av != 0.0f64 {
            let dc = exact_dec(av)
            let s = round_sig(&dc, digits)
            kp = s.e10
            var nd = digits
            while nd > 1usize && s.d[nd - 1usize] == 0u8 { nd -= 1usize }
            nsig = i64(nd)
        }
        let left = kp + 1i64
        var sleft = 1i64
        if left > 0i64 { sleft = left }
        if isneg { sleft += 1i64 }
        if isneg { neg = true }
        var rgt = nsig - kp - 1i64
        if rgt < 0i64 { rgt = 0i64 }
        if !any || sleft > mxsl { mxsl = sleft }
        if !any || rgt > mxrgt { mxrgt = rgt }
        if kp > mxe { mxe = kp }
        if kp < mne { mne = kp }
        if nsig > mxns { mxns = nsig }
        any = true
        i += 1usize
    }
    if !any {
        f.fixed = true
        f.w = 1usize
        ret f
    }
    var e = 1i64
    if mxe >= 100i64 || mne <= -100i64 { e = 2i64 }
    let d = mxns - 1i64
    var ws = d + 4i64 + e
    if d > 0i64 { ws += 1i64 }
    if neg { ws += 1i64 }
    var wf = mxsl + mxrgt
    if mxrgt != 0i64 { wf += 1i64 }
    if wf <= ws {
        f.fixed = true
        f.w = usize(wf)
        f.d = usize(mxrgt)
    } else {
        f.fixed = false
        f.w = usize(ws)
        f.d = usize(d)
    }
    ret f
}

// one value in the layout f, right-justified to at least width characters
fn put_formatted(w: *W, v: f64, f: *const Fmt, width: usize) {
    var wd = f.w
    if width > wd { wd = width }
    let start = w.n
    var av = v
    if v < 0.0f64 {
        put(w, 45u8)
        av = 0.0f64 - v
    }
    if f.fixed { put_fixed(w, av, f.d) } else { put_sci(w, av, f.d) }
    let used = w.n - start
    if used < wd {
        // shift right by the padding
        let gap = wd - used
        var i = used
        while i > 0usize {
            i -= 1usize
            w.b[start + i + gap] = w.b[start + i]
        }
        var k = 0usize
        while k < gap {
            w.b[start + k] = 32u8
            k += 1usize
        }
        w.n = start + wd
    }
}

fn one_width(v: f64, digits: usize, tmp: []u8) -> usize {
    var vv: [1]f64 = zero
    vv[0usize] = v
    var w: W = zero
    w.b = tmp
    let f = real_info(vv[0usize..1usize], digits)
    put_formatted(&w, v, &f, 0usize)
    ret w.n
}

// ---- terms

// the order of format_one_response: reorder.earth(decomp = "anova") over the selected terms
fn anova_order(a: *mem.Arena, f: *const ef.EFit, order: []usize) -> err {
    let k = f.nsel
    let p = f.p
    let (kd, e1) = mem.alloc[f64](a, k)
    let (kl, e2) = mem.alloc[f64](a, k)
    let (kx, e3) = mem.alloc[f64](a, k)
    let (kc, e4) = mem.alloc[f64](a, k)
    let (kp, e5) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Exhausted }
    var i = 0usize
    while i < k {
        let t = f.sel[i]
        var deg = 0usize
        var lin = 0usize
        var u1 = 0usize
        var u2 = 0usize
        var u3 = 0usize
        var nu = 0usize
        var first = 0usize
        var j = 0usize
        while j < p {
            let dv = f.dirs[t + j * f.nt]
            if dv != 0i64 {
                deg += 1usize
                if nu == 0usize { u1 = j + 1usize }
                if nu == 1usize { u2 = j + 1usize }
                if nu == 2usize { u3 = j + 1usize }
                if nu == 0usize { first = j }
                nu += 1usize
            }
            if dv == 2i64 { lin += 1usize }
            j += 1usize
        }
        kd[i] = f64(deg)
        kl[i] = 0.0f64 - f64(lin)
        kx[i] = 0.0f64
        kc[i] = 0.0f64
        kp[i] = 0.0f64
        if i > 0usize && nu > 0usize {
            var key = 1.0e6f64 * f64(u1)
            if nu >= 2usize {
                key += 1.0e3f64 * f64(u2)
                if nu >= 3usize { key += f64(u3) }
            }
            kx[i] = key
            kc[i] = f.cuts[t + first * f.nt]
            if f.dirs[t + first * f.nt] == 1i64 { kp[i] = 1.0f64 }
        }
        order[i] = i
        i += 1usize
    }
    // stable insertion sort on (kd, kl, kx, kc, kp)
    i = 1usize
    while i < k {
        let cur = order[i]
        var q = i
        var go = true
        while q > 0usize && go {
            let o = order[q - 1usize]
            var lt = false
            if kd[cur] != kd[o] {
                lt = kd[cur] < kd[o]
            } else if kl[cur] != kl[o] {
                lt = kl[cur] < kl[o]
            } else if kx[cur] != kx[o] {
                lt = kx[cur] < kx[o]
            } else if kc[cur] != kc[o] {
                lt = kc[cur] < kc[o]
            } else {
                lt = kp[cur] < kp[o]
            }
            if lt {
                order[q] = o
                q -= 1usize
            } else {
                go = false
            }
        }
        order[q] = cur
        i += 1usize
    }
    ret ok
}

type Names = struct { b: []const u8, off: []const usize }

fn put_name(w: *W, nm: *const Names, j: usize) {
    put_str(w, nm.b[nm.off[j]..nm.off[j + 1usize]], nm.off[j + 1usize] - nm.off[j])
}

fn name_len(nm: *const Names, j: usize) -> usize {
    ret nm.off[j + 1usize] - nm.off[j]
}

// colnames(bx) of the selected term t: "h(%g-%s)" for a left hinge, "h(%s-%g)" for a right hinge
fn put_term_name(w: *W, f: *const ef.EFit, nm: *const Names, t: usize) {
    if t == 0usize {
        put_lit(w, "(Intercept)")
        ret
    }
    var first = true
    var j = 0usize
    while j < f.p {
        let dv = f.dirs[t + j * f.nt]
        if dv != 0i64 {
            if !first { put(w, 42u8) }
            first = false
            if dv == 2i64 {
                put_name(w, nm, j)
            } else if dv == -1i64 {
                put_lit(w, "h(")
                put_g(w, f.cuts[t + j * f.nt], 6usize)
                put(w, 45u8)
                put_name(w, nm, j)
                put(w, 41u8)
            } else {
                put_lit(w, "h(")
                put_name(w, nm, j)
                put(w, 45u8)
                put_g(w, f.cuts[t + j * f.nt], 6usize)
                put(w, 41u8)
            }
        }
        j += 1usize
    }
}

// the width get.term.strings.pmax prints each element of the expression in
fn pmax_width(f: *const ef.EFit, nm: *const Names, digits: usize, tmp: []u8) -> usize {
    if f.nsel == 1usize { ret 10usize }
    var width = 0usize
    var j = 0usize
    while j < f.p {
        var used = false
        var i = 0usize
        while i < f.nsel {
            if f.dirs[f.sel[i] + j * f.nt] != 0i64 { used = true }
            i += 1usize
        }
        if used {
            let nl = name_len(nm, j)
            if nl > width { width = nl }
            i = 0usize
            while i < f.nsel {
                let cw = one_width(f.cuts[f.sel[i] + j * f.nt], digits, tmp)
                if cw > width { width = cw }
                i += 1usize
            }
        }
        j += 1usize
    }
    ret width
}

fn put_pmax_term(w: *W, f: *const ef.EFit, nm: *const Names, t: usize, width: usize, digits: usize, fname: str) {
    var first = true
    var j = 0usize
    var vv: [1]f64 = zero
    while j < f.p {
        let dv = f.dirs[t + j * f.nt]
        if dv != 0i64 {
            if !first { put_lit(w, "* ") }
            first = false
            let cut = f.cuts[t + j * f.nt]
            vv[0usize] = cut
            let fm = real_info(vv[0usize..1usize], digits)
            let nl = name_len(nm, j)
            var gap = 0usize
            if width > nl { gap = width - nl }
            if dv == 2i64 {
                put_name(w, nm, j)
                pad(w, gap)
                put(w, 32u8)
                pad(w, width)
                pad(w, 12usize)
            } else if dv == -1i64 {
                put_lit(w, fname)
                put_formatted(w, cut, &fm, width)
                put_lit(w, " - ")
                pad(w, gap)
                put_name(w, nm, j)
                put_lit(w, ") ")
            } else {
                put_lit(w, fname)
                pad(w, gap)
                put_name(w, nm, j)
                put_lit(w, " - ")
                put_formatted(w, cut, &fm, width)
                put_lit(w, ") ")
            }
        }
        j += 1usize
    }
}

// ---- format.earth

// style: 0 "h", 1 "pmax", 2 "max", 3 "bf". coefs: the nsel coefficients in selected-term order (the earth coefficients of a response, or the glm's).
// Answers the text of format_one_response, newline-terminated lines
fn format_one(a: *mem.Arena, f: *const ef.EFit, nm: *const Names, style: usize, digits: usize, coefs: []const f64, w: *W) -> err {
    let k = f.nsel
    let p = f.p
    let (order, e1) = mem.alloc[usize](a, k)
    if e1 != ok { ret e1 }
    let eo = anova_order(a, f, order)
    if eo != ok { ret eo }
    let (cs, e2) = mem.alloc[f64](a, k)
    let (ac, e3) = mem.alloc[f64](a, k)
    let (tmp, e4) = mem.alloc[u8](a, 512usize)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Exhausted }
    var i = 0usize
    while i < k {
        cs[i] = coefs[order[i]]
        i += 1usize
    }
    var cw = 10usize
    if k > 1usize {
        i = 1usize
        while i < k {
            var v = cs[i]
            if v < 0.0f64 { v = 0.0f64 - v }
            ac[i - 1usize] = v
            i += 1usize
        }
        let fv = real_info(ac[0usize..k - 1usize], digits)
        cw = fv.w
    }
    // the term strings
    let tsl = 512usize + 200usize * p
    let (tb, e5) = mem.alloc[u8](a, k * tsl)
    let (tl, e6) = mem.alloc[usize](a, k)
    if e5 != ok || e6 != ok { ret mem.Exhausted }
    var width = 0usize
    if style == 1usize || style == 2usize { width = pmax_width(f, nm, digits, tmp) }
    i = 0usize
    while i < k {
        var tw: W = zero
        tw.b = tb[i * tsl..i * tsl + tsl]
        let t = f.sel[order[i]]
        if style == 1usize || style == 2usize {
            if i == 0usize {
                put_lit(&tw, "(Intercept)")
            } else if style == 1usize {
                put_pmax_term(&tw, f, nm, t, width, digits, "pmax(0, ")
            } else {
                put_pmax_term(&tw, f, nm, t, width, digits, "max(0, ")
            }
        } else {
            put_term_name(&tw, f, nm, t)
        }
        tl[i] = tw.n
        i += 1usize
    }
    // bf: the originals and their new names
    var nb = 0usize
    var ob: []u8 = tb[0usize..0usize]
    var ol: []usize = tl[0usize..0usize]
    var os: []usize = tl[0usize..0usize]
    if style == 3usize {
        let (hb, e7) = mem.alloc[u8](a, k * tsl)
        let (ps, e8) = mem.alloc[usize](a, k * p + 2usize)
        let (pl, e9) = mem.alloc[usize](a, k * p + 2usize)
        if e7 != ok || e8 != ok || e9 != ok { ret mem.Exhausted }
        i = 0usize
        while i < k * tsl {
            hb[i] = tb[i]
            i += 1usize
        }
        i = 0usize
        while i < k {
            var at = 0usize
            while at <= tl[i] {
                if at == tl[i] || hb[i * tsl + at] == 42u8 {
                    // a piece ends here
                    var st = at
                    // find the piece start
                    var s0 = at
                    while s0 > 0usize && hb[i * tsl + s0 - 1usize] != 42u8 { s0 -= 1usize }
                    st = s0
                    let len = at - st
                    var dup = false
                    var q = 0usize
                    while q < nb {
                        if pl[q] == len {
                            var same = true
                            var c = 0usize
                            while c < len {
                                if hb[ps[q] + c] != hb[i * tsl + st + c] { same = false }
                                c += 1usize
                            }
                            if same { dup = true }
                        }
                        q += 1usize
                    }
                    if !dup {
                        ps[nb] = i * tsl + st
                        pl[nb] = len
                        nb += 1usize
                    }
                }
                at += 1usize
            }
            i += 1usize
        }
        ob = hb
        ol = pl
        os = ps
        // gsub(fixed) of every original but the first by its bf name, over all the term strings in turn
        let (sw, e10) = mem.alloc[u8](a, tsl)
        if e10 != ok { ret mem.Exhausted }
        var q = 1usize
        while q < nb {
            var tn: W = zero
            tn.b = sw
            put_lit(&tn, "bf")
            put_uint(&tn, i64(q))
            let rl = tn.n
            i = 0usize
            while i < k {
                var out: W = zero
                out.b = sw[rl..tsl]
                var at = 0usize
                let base = i * tsl
                let tlen = tl[i]
                while at < tlen {
                    var hit = false
                    if at + ol[q] <= tlen {
                        hit = true
                        var c = 0usize
                        while c < ol[q] {
                            if tb[base + at + c] != ob[os[q] + c] { hit = false }
                            c += 1usize
                        }
                    }
                    if hit {
                        var c2 = 0usize
                        while c2 < rl {
                            put(&out, sw[c2])
                            c2 += 1usize
                        }
                        at += ol[q]
                    } else {
                        put(&out, tb[base + at])
                        at += 1usize
                    }
                }
                var c3 = 0usize
                while c3 < out.n {
                    tb[base + c3] = sw[rl + c3]
                    c3 += 1usize
                }
                tl[i] = out.n
                i += 1usize
            }
            q += 1usize
        }
    }
    // the lines
    put_lit(w, "  ")
    put_g(w, cs[0usize], digits)
    put(w, 10u8)
    i = 1usize
    while i < k {
        var fm: Fmt = zero
        var v = cs[i]
        var vv: [1]f64 = zero
        if v < 0.0f64 {
            put_lit(w, "  - ")
            v = 0.0f64 - v
        } else {
            put_lit(w, "  + ")
        }
        vv[0usize] = v
        fm = real_info(vv[0usize..1usize], digits)
        put_formatted(w, v, &fm, cw)
        put_lit(w, " * ")
        var c = 0usize
        while c < tl[i] {
            let ch = tb[i * tsl + c]
            if style == 3usize && ch == 42u8 {
                put_lit(w, " * ")
            } else {
                put(w, ch)
            }
            c += 1usize
        }
        put(w, 10u8)
        i += 1usize
    }
    if style == 3usize {
        put(w, 10u8)
        var q = 1usize
        while q < nb {
            var tn: W = zero
            tn.b = tmp
            put_lit(&tn, "bf")
            put_uint(&tn, i64(q))
            pad(w, 6usize - tn.n)
            put_str(w, tmp, tn.n)
            put_lit(w, "  ")
            put_str(w, ob[os[q]..os[q] + ol[q]], ol[q])
            put(w, 10u8)
            q += 1usize
        }
    }
    ret ok
}

// format.earth for response resp: the text lines of the earth coefficients. Names: the predictor names, off[j]..off[j + 1] being name j
fn format_earth(a: *mem.Arena, f: *const ef.EFit, nmb: []const u8, noff: []const usize, style: usize, digits: usize, resp: usize, glm_coef: []const f64) -> ([]u8, err) {
    var nm: Names = zero
    nm.b = nmb
    nm.off = noff
    let cap = 4096usize + f.nsel * (f.p * 260usize + 512usize)
    let (buf, e1) = mem.alloc[u8](a, cap)
    if e1 != ok { ret (buf, e1) }
    var w: W = zero
    w.b = buf
    var cf: []const f64 = f.coef[resp * f.nsel..resp * f.nsel + f.nsel]
    if glm_coef.len == f.nsel { cf = glm_coef }
    let e2 = format_one(a, f, &nm, style, digits, cf, &w)
    ret (buf[0usize..w.n], e2)
}
