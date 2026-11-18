// e.algo.gmp over e.algo.bignum against gmp. tests/oracle/gmp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gmp`; the layout is at the top of scripts/r_oracle/groups/gmp.R.

use e.algo.bignum as bn
use e.algo.gmp as g
use e.io
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
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
