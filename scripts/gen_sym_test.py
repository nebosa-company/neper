"""Generates tests/selfhost/fixtures/link/math_sym/src/main.e (L154) against SymPy.

Every expectation is a number SymPy or mpmath computes independently of the module:
evaluation by lambdify, derivatives by sympy.diff then lambdify, integrals as the numeric
definite integral (mpmath quadrature through sympy.Integral.evalf, not SymPy's own
antiderivative), roots from sympy.solve filtered to the real ones. The fixture compares by
value because the module's simplification is minimal and its forms differ from SymPy's.

    PYTHONPATH=<dir with sympy, mpmath> python scripts/gen_sym_test.py
"""
import math
import os
import random
import struct

import sympy
from sympy import Symbol, symbols, sympify

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "math_sym", "src", "main.e")
x, y = symbols("x y")
ENV = {"x": x, "y": y, "ln": sympy.log, "log": sympy.log, "atan": sympy.atan, "sqrt": sympy.sqrt, "exp": sympy.exp}


def bits(v):
    return "%016x" % struct.unpack("<Q", struct.pack("<d", float(v)))[0]


def hx(s):
    return s.encode().hex()


def parse(src):
    return sympify(src.replace("^", "**"), locals=ENV)


EVAL_EXPRS = [
    "1+2*3", "2^10", "x", "x+1", "x*x+2*x+1", "(x+1)^2", "x^3-2*x^2+x-5", "1/x", "x/(x^2+1)", "(x-1)/(x+1)",
    "sin(x)", "cos(x)^2+sin(x)^2", "tan(x)", "exp(x)", "exp(-x^2)", "ln(x)", "atan(x)", "sqrt(x)", "x^(1/2)", "x^(3/2)",
    "x^-2", "-x^2", "2*x^-1", "sin(2*x)*cos(3*x)", "exp(x)*ln(x)", "(x+y)^3", "x*y+x/y", "x^y", "sqrt(x^2+y^2)",
    "0.5*x+0.25", "3.14159*x", "1/3*x^3", "x**2 + y**2", "-(x+1)*(x-1)", "ln(x^2+1)", "sin(x)/x", "exp(x)/(1+exp(x))",
    "x^5-3*x^4+2*x^3", "(x^2+1)^(1/2)", "1/(1+x^2)", "atan(x)/(1+x^2)", "pi*x", "x^2^0.5",
]
DIFF_EXPRS = [
    "x^3", "3*x^2+2*x+1", "x^10-x^5", "1/x", "x^(1/2)", "x^(-3)", "sin(x)", "cos(x)", "tan(x)", "exp(x)", "ln(x)", "atan(x)",
    "x*sin(x)", "x^2*exp(x)", "sin(x)*cos(x)", "exp(2*x)", "sin(3*x+1)", "cos(x^2)", "ln(x^2+1)", "exp(sin(x))",
    "(x^2+1)^3", "(2*x+1)^(1/2)", "x/(x^2+1)", "(x-1)/(x+1)", "1/(1+x^2)", "x^x", "x^(x^2)", "2^x", "sin(x)^2", "tan(x)^2",
    "exp(x)*ln(x)", "ln(ln(x))", "atan(2*x)", "x*y^2+y*x^3", "(x+y)^5", "sqrt(1+x^2)", "exp(-x^2/2)", "x^3*ln(x)",
]
INT_EXPRS = [  # (expr, a, b): the definite integral is computed numerically
    ("3", 0.0, 2.0), ("x", 0.0, 3.0), ("x^2", -1.0, 2.0), ("x^3-2*x+1", 0.0, 2.0), ("(x+1)^3", 0.0, 1.0), ("(2*x+1)*(x-3)", -1.0, 2.0),
    ("1/x", 1.0, 3.0), ("x^(-2)", 1.0, 4.0), ("x^(1/2)", 0.0, 4.0), ("sin(x)", 0.0, 1.5), ("cos(x)", 0.0, 1.0), ("exp(x)", 0.0, 2.0),
    ("exp(2*x)", 0.0, 1.0), ("sin(3*x+1)", 0.0, 1.0), ("cos(2*x)", 0.0, 2.0), ("1/(2*x+3)", 0.0, 2.0), ("(3*x+1)^5", 0.0, 1.0),
    ("(3*x+1)^(-2)", 0.0, 2.0), ("x*exp(x)", 0.0, 1.0), ("x^2*exp(x)", 0.0, 2.0), ("x*sin(x)", 0.0, 3.0), ("x^2*cos(x)", 0.0, 2.0),
    ("(x+1)*sin(2*x)", 0.0, 1.0), ("x^3*exp(-x)", 0.0, 2.0), ("(2*x+1)*cos(3*x-1)", 0.0, 1.0), ("x+sin(x)+exp(x)", 0.0, 1.0),
    ("5*sin(x)", 0.0, 1.0), ("y*x", 0.0, 1.0), ("tan(x)", 0.0, 1.0), ("ln(x)", 1.0, 3.0),
]
UNSUPPORTED_INT = ["exp(x^2)", "sin(x)/x", "1/(1+x^2)", "sin(x)*cos(x)", "ln(x)*x"]


def real_roots(src):
    e = parse(src)
    sols = sympy.solve(e, x)
    out = []
    for s in sols:
        v = complex(sympy.N(s))
        if abs(v.imag) < 1e-12:
            out.append(v.real)
    return sorted(out)


SOLVE_EXPRS = [
    "2*x-4", "3*x+1", "x^2-1", "x^2-5*x+6", "x^2+x-1", "x^2+1", "x^2", "2*x^2-3*x-2", "x^2-2", "9*x^2-1", "x^3-x", "x^3-6*x^2+11*x-6",
    "x^4-1", "x^4-5*x^2+4", "x^3+x^2+x+1", "2*x^3-3*x^2-3*x+2", "x^5-x", "6*x^3-11*x^2+6*x-1", "x^2/2-x/3-1", "(x-1)*(x-2)*(x+3)",
    "x^2-0.25", "0.5*x-3", "x^3-3*x^2+3*x-1", "4*x^2-4*x+1",
]
UNSUPPORTED_SOLVE = ["sin(x)", "exp(x)-2", "x^5-x-1", "1/x-2", "x^3-2", "x^6-1"]


def rec(kind, src, var, *numbers_groups):
    parts = [kind, hx(src), hx(var)]
    for g in numbers_groups:
        parts.append(str(len(g)))
        parts.extend(bits(v) for v in g)
    return " ".join(parts) + ";"


def main():
    rnd = random.Random(154)
    rows = []
    pts = [0.5, 1.5, 2.25, -0.75, 3.0]
    for src in EVAL_EXPRS:
        e = parse(src)
        vals, ptsxy = [], []
        for px in pts[:4]:
            py = rnd.choice([0.5, 2.0, 1.25, 3.5])
            try:
                v = complex(e.subs({x: px, y: py}).evalf())
            except Exception:
                continue
            if abs(v.imag) > 1e-12 or not math.isfinite(v.real):
                continue
            ptsxy += [px, py]
            vals.append(v.real)
        if vals:
            rows.append(rec("E", src, "x", ptsxy, vals))
    for src in DIFF_EXPRS:
        e = parse(src)
        d = sympy.diff(e, x)
        vals, ps = [], []
        for px in [0.5, 1.5, 2.25, 0.75]:
            try:
                v = complex(d.subs({x: px, y: 1.5}).evalf())
            except Exception:
                continue
            if abs(v.imag) > 1e-12 or not math.isfinite(v.real):
                continue
            ps.append(px)
            vals.append(v.real)
        rows.append(rec("D", src, "x", ps, vals))
    for src, a, b in INT_EXPRS:
        e = parse(src).subs(y, 2)
        v = float(sympy.Integral(e, (x, a, b)).evalf(20))
        rows.append(rec("I", src.replace("y", "2"), "x", [a, b], [v]))
    for src in UNSUPPORTED_INT:
        rows.append(rec("N", src, "x", [], []))
    for src in SOLVE_EXPRS:
        roots = real_roots(src)
        rows.append(rec("S", src, "x", [], roots))
    for src in UNSUPPORTED_SOLVE:
        rows.append(rec("U", src, "x", [], []))
    # random polynomials with chosen rational roots
    for _ in range(30):
        rts = [sympy.Rational(rnd.randint(-6, 6), rnd.choice([1, 1, 2, 3])) for _ in range(rnd.randint(1, 4))]
        lead = rnd.choice([1, 2, 3, -1])
        poly = sympy.expand(lead * sympy.prod([(x - r) for r in rts]))
        src = str(poly).replace("**", "^")
        rows.append(rec("S", src, "x", [], real_roots(src)))
    chunks, calls = [], []
    per = 25
    for k in range(0, len(rows), per):
        chunks.append('fn vectors_%d() -> str {\n    ret "%s"\n}\n' % (k // per, "".join(rows[k:k + per])))
        calls.append("    let r%d = run_chunk(a, vectors_%d())\n    if r%d != 0u32 { os.exit(%di32) }" % (k // per, k // per, k // per, k // per + 1))
    tpl = open(os.path.join(ROOT, "scripts", "sym_fixture_template.e"), encoding="utf-8").read()
    src = tpl.replace("@CHUNKS@", "\n".join(chunks)).replace("@CALLS@", "\n".join(calls))
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    print("records:", len(rows))


main()
