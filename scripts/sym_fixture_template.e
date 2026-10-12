// `e.math.sym` against SymPy and mpmath (scripts/gen_sym_test.py): parse and evaluate, differentiate, integrate (the
// definite integral SymPy's numeric quadrature gives, compared to F(b) - F(a) of the module's antiderivative) and
// solve (SymPy's real roots), each by value. Records: kind, hex expression, hex variable, then counted groups of
// f64 bit patterns. Every check has its own exit code.
use e.io
use e.math.sym as sym
use e.mem
use e.os
use e.str

fn nib(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn token_end(v: str, from: usize) -> usize {
    var i = from
    while v[i] != 32u8 && v[i] != 59u8 { i += 1usize }
    ret i
}

fn number(v: str, from: usize, end: usize) -> usize {
    var out = 0usize
    var i = from
    while i < end {
        out = out * 10usize + usize(v[i] - 48u8)
        i += 1usize
    }
    ret out
}

fn unhex(a: *mem.Arena, v: str, from: usize, end: usize) -> str {
    let count = (end - from) / 2usize
    let (buf, e) = mem.alloc[u8](a, count + 1usize)
    if e != ok { os.exit(80i32) }
    var k = 0usize
    while k < count {
        buf[k] = (nib(v[from + 2usize * k]) << 4u8) | nib(v[from + 2usize * k + 1usize])
        k += 1usize
    }
    ret buf[0usize..count]
}

fn f64_at(v: str, from: usize) -> f64 {
    var bits = 0u64
    var k = 0usize
    while k < 16usize {
        bits = (bits << 4u64) | u64(nib(v[from + k]))
        k += 1usize
    }
    ret mem.bitcast[f64](bits)
}

fn close(got: f64, want: f64) -> bool {
    if !(got == got) { ret false }
    var d = got - want
    if d < 0.0f64 { d = 0.0f64 - d }
    var scale = want
    if scale < 0.0f64 { scale = 0.0f64 - scale }
    if scale < 1.0f64 { scale = 1.0f64 }
    ret d <= 1e-9f64 * scale
}

fn show(what: str, got: str) {
    let p = io.print("\nFAIL ")
    let q = io.print(what)
    let r = io.print(" ")
    let s = io.print(got)
    let t = io.print("\n")
}

// 0 when every record agrees, else 1 + the index of the first that does not.
fn run_chunk(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        let kind = v[i]
        i += 2usize
        var e = token_end(v, i)
        let src = unhex(a, v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let var_name = unhex(a, v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let n1 = number(v, i, e)
        i = e + 1usize
        let g1 = i
        i += n1 * 17usize
        e = token_end(v, i)
        let n2 = number(v, i, e)
        i = e + 1usize
        let g2 = i
        i += n2 * 17usize
        i += 0usize
        // the record ends at its `;`
        while v[i - 1usize] != 59u8 && i < v.len { i += 1usize }
        let (pl, pe) = sym.pool(a, 2048usize)
        if pe != ok { ret 1000u32 }
        var p = pl
        let (expr, se) = sym.parse(&p, src)
        if se != ok {
            show("parse", src)
            ret seen + 1u32
        }
        let xs = sym.symbol_index(&p, sym.sym(&p, var_name))
        var names: [2]str = zero
        names[0] = "x"
        names[1] = "y"
        var values: [2]f64 = zero
        if kind == 69u8 {
            // E: pairs (x, y) then values
            var k = 0usize
            while k < n2 {
                values[0] = f64_at(v, g1 + (2usize * k) * 17usize)
                values[1] = f64_at(v, g1 + (2usize * k + 1usize) * 17usize)
                let got = sym.eval(&p, expr, names[0usize..2usize], values[0usize..2usize])
                if !close(got, f64_at(v, g2 + k * 17usize)) {
                    show("eval", src)
                    ret seen + 1u32
                }
                k += 1usize
            }
            // print and read back: the same value
            let (text_form, te) = sym.to_string(a, &p, expr)
            if te != ok { ret seen + 1u32 }
            let (again, ae) = sym.parse(&p, text_form)
            if ae != ok {
                show("reparse", text_form)
                ret seen + 1u32
            }
            k = 0usize
            while k < n2 {
                values[0] = f64_at(v, g1 + (2usize * k) * 17usize)
                values[1] = f64_at(v, g1 + (2usize * k + 1usize) * 17usize)
                let g0 = sym.eval(&p, expr, names[0usize..2usize], values[0usize..2usize])
                let g1v = sym.eval(&p, again, names[0usize..2usize], values[0usize..2usize])
                if !close(g1v, g0) {
                    show("round trip", text_form)
                    ret seen + 1u32
                }
                k += 1usize
            }
        }
        if kind == 68u8 {
            let d = sym.diff(&p, expr, xs)
            var k = 0usize
            while k < n1 {
                values[0] = f64_at(v, g1 + k * 17usize)
                values[1] = 1.5f64
                let got = sym.eval(&p, d, names[0usize..2usize], values[0usize..2usize])
                if !close(got, f64_at(v, g2 + k * 17usize)) {
                    show("diff", src)
                    ret seen + 1u32
                }
                k += 1usize
            }
        }
        if kind == 73u8 {
            let (anti, good) = sym.integrate(&p, expr, xs)
            if !good {
                show("integrate refused", src)
                ret seen + 1u32
            }
            values[1] = 2.0f64
            values[0] = f64_at(v, g1 + 17usize)
            let hi = sym.eval(&p, anti, names[0usize..2usize], values[0usize..2usize])
            values[0] = f64_at(v, g1)
            let lo = sym.eval(&p, anti, names[0usize..2usize], values[0usize..2usize])
            if !close(hi - lo, f64_at(v, g2)) {
                show("integral", src)
                ret seen + 1u32
            }
            // and the derivative of the antiderivative is the integrand
            let back = sym.diff(&p, anti, xs)
            values[0] = 0.8f64
            let want = sym.eval(&p, expr, names[0usize..2usize], values[0usize..2usize])
            let got = sym.eval(&p, back, names[0usize..2usize], values[0usize..2usize])
            if !close(got, want) {
                show("d/dx of antiderivative", src)
                ret seen + 1u32
            }
        }
        if kind == 78u8 {
            let (_, good) = sym.integrate(&p, expr, xs)
            if good {
                show("integrate should refuse", src)
                ret seen + 1u32
            }
        }
        if kind == 83u8 || kind == 85u8 {
            var roots: [24]u32 = zero
            let (n, re) = sym.solve(&p, expr, xs, roots[0usize..24usize])
            if kind == 85u8 {
                if re != sym.Unsupported {
                    show("solve should be unsupported", src)
                    ret seen + 1u32
                }
            } else {
                if re != ok || n != n2 {
                    show("solve count", src)
                    ret seen + 1u32
                }
                // roots ascending
                var vals: [24]f64 = zero
                var k = 0usize
                while k < n {
                    vals[k] = sym.eval(&p, roots[k], names[0usize..2usize], values[0usize..2usize])
                    k += 1usize
                }
                var a1 = 1usize
                while a1 < n {
                    var b1 = a1
                    while b1 > 0usize && vals[b1] < vals[b1 - 1usize] {
                        let t = vals[b1]
                        vals[b1] = vals[b1 - 1usize]
                        vals[b1 - 1usize] = t
                        b1 -= 1usize
                    }
                    a1 += 1usize
                }
                k = 0usize
                while k < n {
                    if !close(vals[k], f64_at(v, g2 + k * 17usize)) {
                        show("root", src)
                        ret seen + 1u32
                    }
                    k += 1usize
                }
            }
        }
        seen += 1u32
    }
    ret 0u32
}

@CHUNKS@
fn main(a: *mem.Arena, args: []str) -> err {
@CALLS@
    // printing: a few exact forms
    let (pl, pe) = sym.pool(a, 256usize)
    if pe != ok { os.exit(90i32) }
    var p = pl
    let (e1, s1) = sym.parse(&p, "x^2 - 3*x + 2")
    let (t1, w1) = sym.to_string(a, &p, e1)
    if s1 != ok || w1 != ok || !str.eq(t1, "x^2 - 3*x + 2") { os.exit(91i32) }
    let (e2, s2) = sym.parse(&p, "(x+1)/(x-1)")
    let (t2, w2) = sym.to_string(a, &p, e2)
    if s2 != ok || w2 != ok || !str.eq(t2, "(x + 1)*(x - 1)^(-1)") { os.exit(92i32) }
    let (_, bad) = sym.parse(&p, "x + * 2")
    if bad != sym.Syntax { os.exit(93i32) }
    let (_, bad2) = sym.parse(&p, "foo(x")
    if bad2 != sym.Syntax { os.exit(94i32) }
    try io.print("math sym ok")
    ret ok
}
