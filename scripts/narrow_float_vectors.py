"""Independent oracle for f16 and bf16 arithmetic and conversions on the CPU code
generators (D5913), and the generator of the link fixture `narrow_float`.

Section 4 defines every operation as widen to f32, perform the f32 operation, round
once to the narrow type to nearest-even. The reference does exactly that with numpy's
float32 for the operation and an exact rational rounding (`fractions`) for the narrow
format, so nothing here shares a code path with the emitter's integer sequences. The
check run cross-checks the rational rounding against numpy's own float16.

The fixture draws operands from a fixed linear congruential stream (zero/denormal,
infinity/NaN and near-1 exponents are over-represented), folds every result into an
FNV-1a hash per operation and type, and compares each with the hash computed here.
`--emit` writes the fixture; otherwise the script checks the rounding against numpy
and that the committed fixture is what `--emit` would write.
"""
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np

M64 = (1 << 64) - 1
FIXTURE = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/narrow_float/src/main.e"
ITERATIONS = 2500

FORMATS = {
    "f16": dict(tag="h", e=5, m=10, bias=15, nan=0x7E00),
    "bf16": dict(tag="b", e=8, m=7, bias=127, nan=0x7FC0),
}
F32 = dict(e=8, m=23, bias=127, nan=0x7FC00000)
F64 = dict(e=11, m=52, bias=1023, nan=0x7FF8000000000000)

OPS = ["add", "sub", "mul", "div", "sqrt", "neg", "cmp", "to_f32", "to_f64", "from_f32",
       "from_f64", "to_i32", "to_i64", "from_i32", "from_i64", "from_u64", "from_other", "call", "fma"]


def decode(bits, f):
    """-> ('nan',) | ('inf', sign) | ('zero', sign) | ('num', Fraction)."""
    sign = bits >> (f["e"] + f["m"]) & 1
    exp = bits >> f["m"] & ((1 << f["e"]) - 1)
    man = bits & ((1 << f["m"]) - 1)
    if exp == (1 << f["e"]) - 1:
        return ("nan",) if man else ("inf", sign)
    if exp == 0:
        value = Fraction(man, 1 << f["m"]) * Fraction(2) ** (1 - f["bias"])
    else:
        value = Fraction((1 << f["m"]) + man, 1 << f["m"]) * Fraction(2) ** (exp - f["bias"])
    if value == 0:
        return ("zero", sign)
    return ("num", -value if sign else value)


def encode(value, f):
    """Exact round to nearest, ties to even, of a Fraction into the format."""
    if value == 0:
        return 0
    sign = 1 if value < 0 else 0
    a = abs(value)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** e > a:
        e -= 1
    e = max(e, 1 - f["bias"])
    scaled = a / (Fraction(2) ** (e - f["m"]))
    n = scaled.numerator // scaled.denominator
    rest = scaled - n
    if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and n & 1):
        n += 1
    if n == 1 << (f["m"] + 1):
        n >>= 1
        e += 1
    if e > f["bias"]:
        bits = ((1 << f["e"]) - 1) << f["m"]
    elif n < 1 << f["m"]:
        bits = n
    else:
        bits = ((e + f["bias"]) << f["m"]) + n - (1 << f["m"])
    return bits | sign << (f["e"] + f["m"])


def to_bits(d, f):
    if d[0] == "nan":
        return f["nan"]
    if d[0] == "inf":
        return ((1 << f["e"]) - 1) << f["m"] | d[1] << (f["e"] + f["m"])
    if d[0] == "zero":
        return d[1] << (f["e"] + f["m"])
    return encode(d[1], f)


def narrow_of_float(x, f):
    """x is a numpy float32 or float64 value."""
    if np.isnan(x):
        return f["nan"]
    if np.isinf(x):
        return to_bits(("inf", 1 if x < 0 else 0), f)
    if x == 0:
        return to_bits(("zero", 1 if np.signbit(x) else 0), f)
    return encode(Fraction(float(x)), f)


def f32_of(bits, f):
    d = decode(bits, f)
    if d[0] == "nan":
        return np.float32(np.nan)
    if d[0] == "inf":
        return np.float32(-np.inf if d[1] else np.inf)
    if d[0] == "zero":
        return np.float32(-0.0 if d[1] else 0.0)
    return np.float32(float(d[1]))


def fused_f32(x, y, z):
    """x*y+z rounded once to float32: exact in rationals, with IEEE's rules for the specials."""
    fx, fy, fz = float(x), float(y), float(z)
    if any(np.isnan(v) or np.isinf(v) for v in (fx, fy, fz)):
        with np.errstate(all="ignore"):
            return np.float32(np.float64(fx) * np.float64(fy) + np.float64(fz))
    exact = Fraction(fx) * Fraction(fy) + Fraction(fz)
    if exact == 0:
        product_negative = np.signbit(x) != np.signbit(y)
        if fx * fy == 0 and fz == 0:
            return np.float32(-0.0 if product_negative and np.signbit(z) else 0.0)
        return np.float32(0.0)
    return np.uint32(encode(exact, F32)).view(np.float32)


def f32_canon(x):
    if np.isnan(x):
        return F32["nan"]
    return int(np.float32(x).view(np.uint32))


def f64_canon(x):
    if np.isnan(x):
        return F64["nan"]
    return int(np.float64(x).view(np.uint64))


class Stream:
    def __init__(self, seed):
        self.s = seed

    def next(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & M64
        return self.s


def pick(stream, f):
    r = stream.next()
    k = (r >> 33) % 6
    v = r >> 48
    sign = v & (1 << (f["e"] + f["m"]))
    expmask = ((1 << f["e"]) - 1) << f["m"]
    keep = 0xFFFF & ~expmask
    if k == 0:
        if (r >> 20) % 2 == 0:
            return sign | expmask
        return sign | expmask | (v & ((1 << f["m"]) - 1))
    if k == 1:
        return v & keep
    if k == 2:
        return (v & keep) | ((f["bias"] - 2 + (r >> 8) % 5) << f["m"])
    return v


def noise(stream, f, wide_mantissa):
    """The addend for from_f32 (23) and from_f64 (52): random low bits, or around half an ulp."""
    n = stream.next()
    k = (n >> 40) % 4
    shift = wide_mantissa - f["m"] - 1
    if k == 0:
        return n >> 48 if wide_mantissa == 23 else n & ((1 << (wide_mantissa - f["m"] + 1)) - 1)
    return [None, 1 << shift, (1 << shift) - 1, (1 << shift) + 1][k]


def fold(h, out):
    return ((h ^ out) * 1099511628211) & M64


def signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def compare_mask(x, y):
    m = 0
    if x < y: m |= 1
    if x <= y: m |= 2
    if x > y: m |= 4
    if x >= y: m |= 8
    if x == y: m |= 16
    if x != y: m |= 32
    return m


def limit(f):
    return min(((1 << f["e"]) - 1), f["bias"] + 30) << f["m"]


def run(name, op, other_name):
    f = FORMATS[name]
    o = FORMATS[other_name]
    s = Stream(1000 * (1 if name == "f16" else 2) + OPS.index(op) + 7)
    h = 14695981039346656037
    with np.errstate(all="ignore"):
        for _ in range(ITERATIONS):
            xb = pick(s, f)
            yb = pick(s, f)
            x, y = f32_of(xb, f), f32_of(yb, f)
            if op in ("add", "call"): out = narrow_of_float(np.float32(x + y), f)
            elif op == "sub": out = narrow_of_float(np.float32(x - y), f)
            elif op == "mul": out = narrow_of_float(np.float32(x * y), f)
            elif op == "div": out = narrow_of_float(np.float32(x / y), f)
            elif op == "sqrt": out = narrow_of_float(np.sqrt(x), f)
            elif op == "fma":
                zb = pick(s, f)
                out = narrow_of_float(fused_f32(x, y, f32_of(zb, f)), f)
            elif op == "neg": out = narrow_of_float(np.float32(-x), f)
            elif op == "cmp": out = compare_mask(float(x), float(y))
            elif op == "to_f32": out = f32_canon(x)
            elif op == "to_f64": out = f64_canon(np.float64(x))
            elif op == "from_f32":
                w = (f32_canon(x) + noise(s, f, 23)) & 0xFFFFFFFF
                out = narrow_of_float(np.uint32(w).view(np.float32), f)
            elif op == "from_f64":
                w = (f64_canon(np.float64(x)) + noise(s, f, 52)) & M64
                out = narrow_of_float(np.uint64(w).view(np.float64), f)
            elif op in ("to_i32", "to_i64"):
                out = 0
                if (xb & 0x7FFF) < limit(f):
                    out = int(float(x)) & (0xFFFFFFFF if op == "to_i32" else M64)
            elif op in ("from_i32", "from_i64", "from_u64"):
                n = s.next()
                q = n >> ((n >> 5) % 64)
                value = {"from_i32": signed(q, 32), "from_i64": signed(q, 64), "from_u64": q}[op]
                out = encode(Fraction(value), f)
            elif op == "from_other":
                out = to_bits(decode(pick(s, o), o), f)
            else:
                raise SystemExit("unknown op " + op)
            h = fold(h, out)
    return h


LITERALS = {
    "f16": ["1.5", "0.1", "65504.0", "6.103515625e-5", "5.960464477539063e-8", "3.14159", "0.333333",
            "1.0e-3", "2049.0", "2051.0", "4.0e4", "0.0", "1.0009765625", "1.00048828125"],
    "bf16": ["1.0", "0.1", "3.14159", "1.0e38", "1.0e-40", "257.0", "259.0", "0.0", "1.0e-3", "3.38e38"],
}


def emit():
    out = []
    w = out.append
    w("// f16 and bf16 on the x64 and aarch64 code generators (D5913): widen to f32, operate,")
    w("// round once to nearest-even, in integer instructions. Every operation and conversion")
    w(f"// folds {ITERATIONS} operands drawn from a fixed stream (zero and denormal, infinity and NaN,")
    w("// and exponents near 1 are over-represented) into an FNV-1a hash that")
    w("// scripts/narrow_float_vectors.py computes independently: numpy float32 for the f32")
    w("// operation, exact rational rounding for the narrow format. Generated by that script;")
    w("// do not edit. A failure exits with 1 + 20 * type + operation (f16 first), 100 and up")
    w("// for a literal, 250 and up for storage.")
    w("")
    w("use e.gpu")
    w("use e.math")
    w("use e.mem")
    w("use e.os")
    w("")
    w("fn next(s: *u64) -> u64 {")
    w("    *s = *s *% 6364136223846793005u64 +% 1442695040888963407u64")
    w("    ret *s")
    w("}")
    w("")
    w("fn fold(h: u64, out: u64) -> u64 { ret (h ^ out) *% 1099511628211u64 }")
    w("")
    w("fn compare_mask[T: type](x: T, y: T) -> u64 {")
    w("    var m = 0u64")
    w("    if x < y { m = m | 1u64 }")
    w("    if x <= y { m = m | 2u64 }")
    w("    if x > y { m = m | 4u64 }")
    w("    if x >= y { m = m | 8u64 }")
    w("    if x == y { m = m | 16u64 }")
    w("    if x != y { m = m | 32u64 }")
    w("    ret m")
    w("}")
    w("")
    for name, f in FORMATS.items():
        t = f["tag"]
        expmask = ((1 << f["e"]) - 1) << f["m"]
        keep = 0xFFFF & ~expmask
        w(f"fn pick_{t}(s: *u64) -> u16 {{")
        w("    let r = next(s)")
        w("    let k = (r >> 33u64) % 6u64")
        w("    let v = u16(r >> 48u64)")
        w(f"    let sign = v & {1 << (f['e'] + f['m'])}u16")
        w("    if k == 0u64 {")
        w(f"        if (r >> 20u64) % 2u64 == 0u64 {{ ret sign | {expmask}u16 }}")
        w(f"        ret sign | {expmask}u16 | (v & {(1 << f['m']) - 1}u16)")
        w("    }")
        w(f"    if k == 1u64 {{ ret v & {keep}u16 }}")
        w(f"    if k == 2u64 {{ ret (v & {keep}u16) | u16(({f['bias'] - 2}u64 + (r >> 8u64) % 5u64) << {f['m']}u64) }}")
        w("    ret v")
        w("}")
        w("")
    for name, f in FORMATS.items():
        t = f["tag"]
        T = name
        O = "bf16" if name == "f16" else "f16"
        w(f"fn add_{t}(x: {T}, y: {T}) -> {T} {{ ret x + y }}")
        w("")
        w(f"fn run_{t}(op: u64, seed: u64) -> u64 {{")
        w("    var s = seed")
        w("    var h = 14695981039346656037u64")
        w("    var i = 0u64")
        w(f"    while i < {ITERATIONS}u64 {{")
        w(f"        let x = mem.bitcast[{T}](pick_{t}(&s))")
        w(f"        let y = mem.bitcast[{T}](pick_{t}(&s))")
        w("        var out = 0u64")
        w("        if op == 0u64 { out = u64(mem.bitcast[u16](x + y)) }")
        w("        if op == 1u64 { out = u64(mem.bitcast[u16](x - y)) }")
        w("        if op == 2u64 { out = u64(mem.bitcast[u16](x * y)) }")
        w("        if op == 3u64 { out = u64(mem.bitcast[u16](x / y)) }")
        w(f"        if op == 4u64 {{ out = u64(mem.bitcast[u16](math.sqrt[{T}](x))) }}")
        w("        if op == 5u64 { out = u64(mem.bitcast[u16](-x)) }")
        w("        if op == 6u64 { out = compare_mask(x, y) }")
        w("        if op == 7u64 { out = u64(mem.bitcast[u32](f32(x))) }")
        w("        if op == 8u64 { out = mem.bitcast[u64](f64(x)) }")
        for op_index, wide, bits in ((9, 23, "u32"), (10, 52, "u64")):
            shift = wide - f["m"] - 1
            w(f"        if op == {op_index}u64 {{")
            w("            let n = next(&s)")
            w("            let k = (n >> 40u64) % 4u64")
            if wide == 23:
                w("            var add = n >> 48u64")
            else:
                w(f"            var add = n & {(1 << (wide - f['m'] + 1)) - 1}u64")
            w(f"            if k == 1u64 {{ add = {1 << shift}u64 }}")
            w(f"            if k == 2u64 {{ add = {(1 << shift) - 1}u64 }}")
            w(f"            if k == 3u64 {{ add = {(1 << shift) + 1}u64 }}")
            if wide == 23:
                w("            let w = mem.bitcast[f32](u32.trunc(u64(mem.bitcast[u32](f32(x))) + add))")
            else:
                w("            let w = mem.bitcast[f64](mem.bitcast[u64](f64(x)) +% add)")
            w(f"            out = u64(mem.bitcast[u16]({T}(w)))")
            w("        }")
        lim = limit(f)
        w(f"        if op == 11u64 && (mem.bitcast[u16](x) & 32767u16) < {lim}u16 {{ out = u64(mem.bitcast[u32](i32(x))) }}")
        w(f"        if op == 12u64 && (mem.bitcast[u16](x) & 32767u16) < {lim}u16 {{ out = mem.bitcast[u64](i64(x)) }}")
        w("        if op >= 13u64 && op <= 15u64 {")
        w("            let n = next(&s)")
        w("            let q = n >> ((n >> 5u64) % 64u64)")
        w(f"            if op == 13u64 {{ out = u64(mem.bitcast[u16]({T}(mem.bitcast[i32](u32.trunc(q))))) }}")
        w(f"            if op == 14u64 {{ out = u64(mem.bitcast[u16]({T}(mem.bitcast[i64](q)))) }}")
        w(f"            if op == 15u64 {{ out = u64(mem.bitcast[u16]({T}(q))) }}")
        w("        }")
        w("        if op == 16u64 {")
        w(f"            let other = mem.bitcast[{O}](pick_{FORMATS[O]['tag']}(&s))")
        w(f"            out = u64(mem.bitcast[u16]({T}(other)))")
        w("        }")
        w(f"        if op == 17u64 {{ out = u64(mem.bitcast[u16](add_{t}(x, y))) }}")
        w("        if op == 18u64 {")
        w(f"            let z = mem.bitcast[{T}](pick_{t}(&s))")
        w(f"            out = u64(mem.bitcast[u16](math.fma[{T}](x, y, z)))")
        w("        }")
        w("        h = fold(h, out)")
        w("        i += 1u64")
        w("    }")
        w("    ret h")
        w("}")
        w("")
    for name, f in FORMATS.items():
        t = f["tag"]
        w("@gpu(16)")
        w(f"fn kernel_{t}(n: u32, x: []{name}, y: []{name}, out: []{name}) {{")
        w("    let i = usize(gpu.gid.x)")
        w("    if gpu.gid.x >= n { ret }")
        w("    out[i] = x[i] * y[i] + x[i]")
        w("}")
        w("")
        w(f"// A kernel on the CPU backend computes in {name} the way the host does.")
        w(f"fn run_kernel_{t}(a: *mem.Arena) -> err {{")
        w("    let (device, open_error) = gpu.open(a, .Cpu, 0u32)")
        w("    if open_error != ok { ret open_error }")
        w("    defer let _ = gpu.close(device)")
        w("    let (q, queue_error) = gpu.queue(device)")
        w("    if queue_error != ok { ret queue_error }")
        w(f"    let (x, x_error) = mem.alloc[{name}](a, 16usize)")
        w("    if x_error != ok { ret x_error }")
        w(f"    let (y, y_error) = mem.alloc[{name}](a, 16usize)")
        w("    if y_error != ok { ret y_error }")
        w(f"    let (got, got_error) = mem.alloc[{name}](a, 16usize)")
        w("    if got_error != ok { ret got_error }")
        w("    var s = 99u64")
        w("    var at = 0usize")
        w("    while at < 16usize {")
        w(f"        x[at] = mem.bitcast[{name}](pick_{t}(&s))")
        w(f"        y[at] = mem.bitcast[{name}](pick_{t}(&s))")
        w("        at += 1usize")
        w("    }")
        w(f"    let (dx, dx_error) = gpu.upload[{name}](q, x)")
        w("    if dx_error != ok { ret dx_error }")
        w("    defer let _ = gpu.release(q, dx)")
        w(f"    let (dy, dy_error) = gpu.upload[{name}](q, y)")
        w("    if dy_error != ok { ret dy_error }")
        w("    defer let _ = gpu.release(q, dy)")
        w(f"    let (dout, dout_error) = gpu.alloc[{name}](q, 16usize)")
        w("    if dout_error != ok { ret dout_error }")
        w("    defer let _ = gpu.release(q, dout)")
        w(f"    try gpu.launch[kernel_{t}](q, gpu.grid1(16usize), 16u32, dx, dy, dout)")
        w("    try gpu.download(q, dout, got)")
        w("    at = 0usize")
        w("    while at < 16usize {")
        w("        let want = x[at] * y[at] + x[at]")
        w(f"        if mem.bitcast[u16](got[at]) != mem.bitcast[u16](want) {{ ret mem.Exhausted }}")
        w("        at += 1usize")
        w("    }")
        w("    ret ok")
        w("}")
        w("")
    w("fn main(a: *mem.Arena, args: []str) -> err {")
    for ti, (name, f) in enumerate(FORMATS.items()):
        other = "bf16" if name == "f16" else "f16"
        for oi, op in enumerate(OPS):
            seed = 1000 * (ti + 1) + oi + 7
            w(f"    if run_{f['tag']}({oi}u64, {seed}u64) != {run(name, op, other)}u64 {{ os.exit({1 + 20 * ti + oi}i32) }}")
    w("")
    w("    // Literals, rounded to nearest-even from the decimal itself.")
    code = 100
    for name in FORMATS:
        for text in LITERALS[name]:
            w(f"    if mem.bitcast[u16]({text}{name}) != {encode(Fraction(text), FORMATS[name])}u16 {{ os.exit({code}i32) }}")
            code += 1
    w("")
    w("    // Kernels on the CPU backend (the reference a GPU emitter is compared with).")
    w("    if run_kernel_h(a) != ok { os.exit(240i32) }")
    w("    if run_kernel_b(a) != ok { os.exit(241i32) }")
    w("")
    w("    // Storage: an array keeps the sixteen bits through a store and a load.")
    w("    var cells: [3]f16 = zero")
    w("    cells[0usize] = 1.5f16")
    w("    cells[1usize] = 2.25f16")
    w("    cells[2usize] = cells[0usize] * cells[1usize]")
    w(f"    if mem.bitcast[u16](cells[2usize]) != {encode(Fraction(27, 8), FORMATS['f16'])}u16 {{ os.exit(250i32) }}")
    w("    var lanes: [2]bf16 = zero")
    w("    lanes[0usize] = 1.5bf16")
    w("    lanes[1usize] = lanes[0usize] + lanes[0usize]")
    w(f"    if mem.bitcast[u16](lanes[1usize]) != {encode(Fraction(3), FORMATS['bf16'])}u16 {{ os.exit(251i32) }}")
    w("    ret ok")
    w("}")
    return "\n".join(out) + "\n"


def check():
    rng = np.random.default_rng(7)
    f = FORMATS["f16"]
    with np.errstate(all="ignore"):
        for _ in range(20000):
            v = np.uint32(int(rng.integers(0, 1 << 32))).view(np.float32)
            if np.isnan(v):
                continue
            assert narrow_of_float(v, f) == int(np.float16(v).view(np.uint16)), float(v)
    if FIXTURE.exists() and FIXTURE.read_text() != emit():
        raise SystemExit("the fixture is not what --emit writes")
    print("ok")


if __name__ == "__main__":
    if "--emit" in sys.argv:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(emit(), newline="\n")
    else:
        check()
