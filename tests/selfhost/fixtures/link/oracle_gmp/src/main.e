// e.algo.gmp over e.algo.bignum against gmp. tests/oracle/gmp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gmp`; the layout is at the top of scripts/r_oracle/groups/gmp.R.

use e.algo.bignum as bn
use e.algo.gmp as g
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn build(a: *mem.Arena, x: []const f64, at: usize, count: usize) -> bn.Int {
    var v = bn.int_zero(a)
    let (base, e0) = bn.int_from_i64(a, 1000000i64)
    if e0 != ok { os.exit(10) }
    var i = count
    while i > 0usize {
        i -= 1usize
        let (c, e1) = bn.int_from_i64(a, i64(x[at + i]))
        if e1 != ok { os.exit(11) }
        let (m, e2) = bn.int_mul(a, v, base)
        if e2 != ok { os.exit(12) }
        let (s, e3) = bn.int_add(a, m, c)
        if e3 != ok { os.exit(13) }
        v = s
    }
    ret v
}

fn answer_q(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let op = usize(x[0usize])
    let n1 = usize(x[1usize])
    let n2 = usize(x[2usize])
    let n3 = usize(x[3usize])
    let n4 = usize(x[4usize])
    let va = build(a, x, 5usize, n1)
    let vb = build(a, x, 5usize + n1, n2)
    let vc = build(a, x, 5usize + n1 + n2, n3)
    let vd = build(a, x, 5usize + n1 + n2 + n3, n4)
    let (p, pe) = bn.rat_make(a, va, vb)
    let (q, qe) = bn.rat_make(a, vc, vd)
    if pe != ok || qe != ok { os.exit(50) }
    var r: bn.Rat = zero
    if op == 0usize {
        let (t, e) = bn.rat_add(a, p, q)
        if e != ok { os.exit(51) }
        r = t
    } else if op == 1usize {
        let (t, e) = bn.rat_sub(a, p, q)
        if e != ok { os.exit(52) }
        r = t
    } else if op == 2usize {
        let (t, e) = bn.rat_mul(a, p, q)
        if e != ok { os.exit(53) }
        r = t
    } else {
        let (t, e) = bn.rat_div(a, p, q)
        if e != ok { os.exit(54) }
        r = t
    }
    var v = r.num
    if str.starts_with(c.name, "qden") { v = r.den }
    if v.sign == .Negative { v.sign = .Positive }
    if str.ends_with(c.name, "_mod") {
        let (m9, e) = g.mod_1e9(a, v)
        if e != ok { os.exit(55) }
        ret f64(m9)
    }
    let (nd, e2) = g.size_in_base(a, v, 10u8)
    if e2 != ok { os.exit(56) }
    ret f64(nd)
}

fn answer_base(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let radix = u8(x[0usize])
    let n1 = usize(x[1usize])
    let va = build(a, x, 2usize, n1)
    if str.eq(c.name, "base_size") {
        // mpz_sizeinbase: exact for a power-of-two base, otherwise floor(bits ln 2 / ln b) + 1, which may be one too big
        let bits = bn.int_bits(va)
        let rd = usize(radix)
        let pow2 = rd == 2usize || rd == 4usize || rd == 8usize || rd == 16usize || rd == 32usize
        if pow2 {
            var lg = 1usize
            while (1usize << lg) < usize(radix) { lg += 1usize }
            ret f64((bits + lg - 1usize) / lg)
        }
        ret math.floor[f64](f64(bits) * math.log[f64](2.0f64) / math.log[f64](f64(radix))) + 1.0f64
    }
    let (b0, be) = str.builder(a, 64usize)
    if be != ok { os.exit(62) }
    var b = b0
    if bn.int_format(va, &b, radix) != ok { os.exit(61) }
    let st = str.done(&b)
    if str.eq(c.name, "base_len") { ret f64(st.len) }
    var sm = 0.0f64
    var i = 0usize
    while i < st.len {
        let ch = st[i]
        var d = 0u32
        if ch >= 48u8 && ch <= 57u8 { d = u32(ch) - 48u32 } else if ch >= 97u8 && ch <= 122u8 { d = u32(ch) - 87u32 } else { d = u32(ch) - 55u32 }
        sm += f64(i + 1usize) * f64(d)
        i += 1usize
    }
    var md = sm
    while md >= 1000000000.0f64 { md = md - 1000000000.0f64 }
    ret md
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.starts_with(c.name, "base_") { ret answer_base(a, c) }
    if str.starts_with(c.name, "qnum") || str.starts_with(c.name, "qden") { ret answer_q(a, c) }
    let x = c.args
    let op = usize(x[0usize])
    let na = usize(x[1usize])
    let nb = usize(x[2usize])
    let nc = usize(x[3usize])
    let extra = u64(x[4usize])
    let va = build(a, x, 5usize, na)
    let vb = build(a, x, 5usize + na, nb)
    let vc = build(a, x, 5usize + na + nb, nc)
    if op == 14usize {
        // factorize(a): extra 0 is the number of prime factors, k the k-th one (ascending) modulo 1e9
        let (fb, fe) = mem.alloc[bn.Int](a, 256usize)
        if fe != ok { os.exit(42) }
        let (cnt, ce) = g.factorize(a, va, fb)
        if ce != ok { os.exit(43) }
        if extra == 0u64 { ret f64(cnt) }
        if usize(extra) > cnt { os.exit(44) }
        let (fm, fme) = g.mod_1e9(a, fb[usize(extra) - 1usize])
        if fme != ok { os.exit(45) }
        ret f64(fm)
    }
    var r = bn.int_zero(a)
    if op == 0usize {
        let (t, e) = bn.int_add(a, va, vb)
        if e != ok { os.exit(20) }
        r = t
    } else if op == 1usize {
        let (t, e) = bn.int_mul(a, va, vb)
        if e != ok { os.exit(21) }
        r = t
    } else if op == 2usize {
        let (q, _, e) = bn.int_divmod(a, va, vb)
        if e != ok { os.exit(22) }
        r = q
    } else if op == 3usize {
        let (_, m, e) = bn.int_divmod(a, va, vb)
        if e != ok { os.exit(23) }
        r = m
    } else if op == 4usize {
        let (t, e) = bn.int_gcd(a, va, vb)
        if e != ok { os.exit(24) }
        r = t
    } else if op == 5usize {
        let (t, e) = g.lcm(a, va, vb)
        if e != ok { os.exit(25) }
        r = t
    } else if op == 6usize {
        let (t, e) = bn.int_mod_pow(a, va, vb, vc)
        if e != ok { os.exit(26) }
        r = t
    } else if op == 7usize {
        let (t, e) = g.inverse(a, va, vb)
        if e != ok { os.exit(27) }
        r = t
    } else if op == 8usize {
        let (p, e) = g.is_prime(a, va)
        if e != ok { os.exit(28) }
        if p { ret 1.0f64 }
        ret 0.0f64
    } else if op == 9usize {
        let (t, e) = g.next_prime(a, va)
        if e != ok { os.exit(29) }
        r = t
    } else if op == 10usize {
        let (t, e) = g.binomial(a, extra, u64(x[5usize + na]))
        if e != ok { os.exit(30) }
        r = t
    } else if op == 11usize {
        let (t, e) = g.fib_luc(a, extra, false)
        if e != ok { os.exit(31) }
        r = t
    } else if op == 12usize {
        let (t, e) = g.fib_luc(a, extra, true)
        if e != ok { os.exit(32) }
        r = t
    } else {
        let (t, e) = g.factorial(a, extra)
        if e != ok { os.exit(33) }
        r = t
    }
    if str.eq(c.name, "mod9") {
        let (m9, e) = g.mod_1e9(a, r)
        if e != ok { os.exit(40) }
        ret f64(m9)
    }
    let (nd, e2) = g.size_in_base(a, r, 10u8)
    if e2 != ok { os.exit(41) }
    ret f64(nd)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gmp.json")
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
