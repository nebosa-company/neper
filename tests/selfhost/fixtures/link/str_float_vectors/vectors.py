"""Generate src/vectors.e for the str_float_vectors fixture.

    python tests/selfhost/fixtures/link/str_float_vectors/vectors.py

Every expected string and bit pattern comes from exact rational arithmetic (Decimal,
Fraction), never from Neper, and encodes e.str's documented semantics:

- push_f64 / push_f32 (`{}`): the fewest significant digits p (1..17, or 1..9) such that
  the exact value rounded half-to-even to p digits reads back as the same value. That is
  not always the shortest string that reads back: at a power of two the rounding interval
  is lopsided, and the nearest p-digit value can miss it while a farther one hits. The
  point is fixed while the leading digit's exponent is in [-5, 15], scientific otherwise.
- parse_f64 / parse_f32: the nearest value, ties to even; overflow, and a non-zero input
  that rounds to zero, are BadNumber.

The cases: random bit patterns, subnormals, every power of two, powers of ten, exact
halfway strings between adjacent values (up to 767 digits) and their neighbours one digit
either side, 16-20 digit strings, and the edges of the fast paths (2^53, 10^22, 10^-342,
10^308, the subnormal and overflow boundaries).
"""
import decimal
import math
import random
import struct
from fractions import Fraction
from pathlib import Path

decimal.getcontext().prec = 2000
D = decimal.Decimal
HERE = Path(__file__).resolve().parent
rng = random.Random(20260927)


# ---------------------------------------------------------------- exact rounding

def round_binary(x, mant_bits, min_exp, max_exp):
    """Nearest (sign, exponent_field, fraction) of a binary format to the rational x, ties
    to even. mant_bits counts the explicit fraction bits. Returns None on overflow and 0 on
    underflow to zero (the caller decides what those mean)."""
    if x == 0:
        return 0
    sign = 1 if x < 0 else 0
    x = abs(x)
    # exponent e such that 2^e <= x < 2^(e+1)
    e = x.numerator.bit_length() - x.denominator.bit_length()
    if Fraction(2) ** e > x:
        e -= 1
    if Fraction(2) ** (e + 1) <= x:
        e += 1
    if e < min_exp:
        e = min_exp  # subnormal: fixed scale
    scale = Fraction(2) ** (mant_bits - e)
    scaled = x * scale
    q, r = divmod(scaled.numerator, scaled.denominator)
    rem = Fraction(r, scaled.denominator)
    if rem > Fraction(1, 2) or (rem == Fraction(1, 2) and q % 2 == 1):
        q += 1
    if q == 0:
        return 0
    if q >= 1 << (mant_bits + 1):
        q >>= 1
        e += 1
    if e > max_exp:
        return None
    if q < 1 << mant_bits:
        field = 0  # subnormal
        frac = q
    else:
        field = e - min_exp + 1
        frac = q - (1 << mant_bits)
    return (sign, field, frac)


def to_bits64(x):
    r = round_binary(x, 52, -1022, 1023)
    if r is None or r == 0:
        return r
    sign, field, frac = r
    return (sign << 63) | (field << 52) | frac


def to_bits32(x):
    r = round_binary(x, 23, -126, 127)
    if r is None or r == 0:
        return r
    sign, field, frac = r
    return (sign << 31) | (field << 23) | frac


def value64(bits):
    sign = -1 if bits >> 63 else 1
    field = (bits >> 52) & 2047
    frac = bits & ((1 << 52) - 1)
    if field == 0:
        return sign * Fraction(frac) * Fraction(2) ** -1074
    return sign * Fraction(frac + (1 << 52)) * Fraction(2) ** (field - 1075)


def value32(bits):
    sign = -1 if bits >> 31 else 1
    field = (bits >> 23) & 255
    frac = bits & ((1 << 23) - 1)
    if field == 0:
        return sign * Fraction(frac) * Fraction(2) ** -149
    return sign * Fraction(frac + (1 << 23)) * Fraction(2) ** (field - 150)


# ---------------------------------------------------------------- the push rule

def digits_of(x):
    """Exact decimal of a positive rational with a terminating expansion: (digits, exp) with
    x = 0.digits * 10^exp."""
    d = D(x.numerator) / D(x.denominator)
    sign, digs, e = d.as_tuple()
    digs = list(digs)
    while digs and digs[-1] == 0:
        digs.pop()
        e += 1
    return digs, len(digs) + e


def round_digits(digs, exp, p):
    """Round 0.digs * 10^exp half-to-even to p significant digits."""
    head = digs[:p] + [0] * max(0, p - len(digs))
    rest = digs[p:]
    up = False
    if rest:
        if rest[0] > 5:
            up = True
        elif rest[0] == 5:
            up = any(rest[1:]) or head[-1] % 2 == 1
    if up:
        i = p - 1
        while i >= 0 and head[i] == 9:
            head[i] = 0
            i -= 1
        if i < 0:
            # 9...9 rounded up: one more digit in front, and the last one falls off.
            head = ([1] + head)[:p]
            exp += 1
        else:
            head[i] += 1
    while head and head[-1] == 0:
        head.pop()
    return head, exp


def spell(sign, head, exp):
    leading = exp - 1
    out = "-" if sign else ""
    if -5 <= leading <= 15:
        if exp <= 0:
            out += "0." + "0" * (-exp) + "".join(map(str, head))
        else:
            whole = [head[i] if i < len(head) else 0 for i in range(exp)]
            out += "".join(map(str, whole))
            if len(head) > exp:
                out += "." + "".join(map(str, head[exp:]))
    else:
        out += str(head[0])
        if len(head) > 1:
            out += "." + "".join(map(str, head[1:]))
        out += "e" + str(leading)
    return out


def push(bits, width):
    if width == 64:
        field, frac, sign = (bits >> 52) & 2047, bits & ((1 << 52) - 1), bits >> 63
        if field == 2047:
            return "nan" if frac else ("-inf" if sign else "inf")
        value, to_bits, most = value64(bits), to_bits64, 17
    else:
        field, frac, sign = (bits >> 23) & 255, bits & ((1 << 23) - 1), bits >> 31
        if field == 255:
            return "nan" if frac else ("-inf" if sign else "inf")
        value, to_bits, most = value32(bits), to_bits32, 9
    if value == 0:
        return "-0" if sign else "0"
    digs, exp = digits_of(abs(value))
    magnitude = bits & ((1 << (width - 1)) - 1)
    for p in range(1, most + 1):
        head, e = round_digits(digs, exp, p)
        candidate = Fraction(int("".join(map(str, head)))) * Fraction(10) ** (e - len(head))
        if to_bits(candidate) == magnitude:
            return spell(sign, head, e)
    raise AssertionError("no length reads back")


# ---------------------------------------------------------------- the parse rule

def parse(text, width):
    """Expected bits, or None for BadNumber. `text` is always in the accepted grammar."""
    x = Fraction(D(text))
    if x == 0:
        return (1 << (width - 1)) if text.startswith("-") else 0
    bits = to_bits64(x) if width == 64 else to_bits32(x)
    if bits is None or bits == 0:
        return None
    return bits


def decimal_text(x):
    """The exact decimal of a rational with a terminating expansion, in the parser's
    grammar: [-]D[.DDD][e[-]N]."""
    sign = "-" if x < 0 else ""
    digs, exp = digits_of(abs(x))
    body = str(digs[0]) + ("." + "".join(map(str, digs[1:])) if len(digs) > 1 else "")
    return sign + body + "e" + str(exp - 1)


# ---------------------------------------------------------------- the cases

def finite_random64():
    while True:
        bits = rng.getrandbits(64)
        if (bits >> 52) & 2047 != 2047:
            return bits


def finite_random32():
    while True:
        bits = rng.getrandbits(32)
        if (bits >> 23) & 255 != 255:
            return bits


def f64_bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def f32_bits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def format_cases64():
    cases = set()
    for _ in range(3000):
        cases.add(finite_random64())
    for _ in range(400):
        cases.add(rng.getrandbits(52) | (rng.getrandbits(1) << 63))  # subnormals
    for k in range(-1074, 1024):  # every power of two: the lopsided intervals
        cases.add(to_bits64(Fraction(2) ** k))
    for k in range(-323, 309):
        cases.add(f64_bits(float("1e%d" % k)))
    for x in [0.1, 0.2, 0.3, 0.1 + 0.2, 1 / 3, 2 / 3, 4999.5, 1e15, 1e16, 123456789012345680.0,
              2.0 ** 53, 2.0 ** 53 + 2, 9007199254740993.0, 5e-324, 2.2250738585072014e-308,
              2.2250738585072009e-308, 1.7976931348623157e308, 1e-5, 9.9999e-6, 1e-6, 123e-7,
              999999999999999.9, 1e22, 1e23, 0.0, -0.0, math.inf, -math.inf, math.pi, math.e]:
        cases.add(f64_bits(x))
    cases.add(0x7FF8000000000000)
    return sorted(cases)


def format_cases32():
    cases = set()
    for _ in range(2000):
        cases.add(finite_random32())
    for _ in range(300):
        cases.add(rng.getrandbits(23) | (rng.getrandbits(1) << 31))
    for k in range(-149, 128):
        cases.add(to_bits32(Fraction(2) ** k))
    for k in range(-45, 39):
        b = to_bits32(Fraction(D("1e%d" % k)))
        if b:
            cases.add(b)
    for x in ["0.1", "0.2", "0.3", "16777216", "16777217", "3.4028235e38", "1.1754944e-38", "1e-45"]:
        b = to_bits32(Fraction(D(x)))
        if b:
            cases.add(b)
    cases.update([0, 1 << 31, 0x7F800000, 0xFF800000, 0x7FC00000])
    return sorted(cases)


def neighbours(width):
    """Adjacent finite positive pairs (a, b) to take midpoints of."""
    pairs = []
    top = (2047 << 52) if width == 64 else (255 << 23)
    rand = finite_random64 if width == 64 else finite_random32
    mask = (1 << (width - 1)) - 1
    for _ in range(700 if width == 64 else 400):
        a = rand() & mask
        if a + 1 < top:
            pairs.append((a, a + 1))
    for a in [0, 1, 2, 3, (1 << (52 if width == 64 else 23)) - 1, 1 << (52 if width == 64 else 23), top - 2]:
        pairs.append((a, a + 1))
    return pairs


def parse_cases(width):
    value = value64 if width == 64 else value32
    rand = finite_random64 if width == 64 else finite_random32
    cases = []
    # Exact ties, and one unit in the last digit either side of them.
    for a, b in neighbours(width):
        mid = (value(a) + value(b)) / 2
        text = decimal_text(mid)
        cases.append(text)
        mantissa, _, exponent = text.partition("e")
        digits = mantissa.replace(".", "")
        for delta in (-1, 1):
            n = int(digits) + delta
            if n <= 0:
                continue
            s = str(n)
            shifted = int(exponent) - (len(digits) - 1) + (len(s) - 1)
            cases.append(s[0] + ("." + s[1:] if len(s) > 1 else "") + "e" + str(shifted))
    # Shortest spellings of random values, and the same with extra digits.
    for _ in range(1500 if width == 64 else 800):
        bits = rand()
        text = push(bits, width)
        if text in ("nan", "inf", "-inf"):
            continue
        cases.append(text)
        if "e" not in text and "." in text:
            cases.append(text + str(rng.randrange(10)) + str(rng.randrange(1, 10)))
    # 16 to 20 digit integers and fractions: either side of the u64 and 2^53 limits.
    for n in [2 ** 53 - 1, 2 ** 53, 2 ** 53 + 1, 2 ** 64 - 1, 2 ** 64, 2 ** 64 + 1, 10 ** 19, 10 ** 19 - 1,
              18446744073709551615, 12345678901234567890, 9999999999999999999]:
        cases.append(str(n))
    for _ in range(300):
        digits = str(rng.randrange(10 ** 15, 10 ** 20))
        cases.append(digits[0] + "." + digits[1:] + "e" + str(rng.randrange(-30, 30)))
    # The fast paths' edges: 10^22 and 10^23, 10^-342 and 10^308, and far past them.
    for k in list(range(-30, 31)) + [-342, -343, -324, -325, 308, 309, -46, -45, 38, 39, 400, -450]:
        for mantissa in ["1", "9", "4.9", "2.5", "1.7976931348623157", "3.4028235", "2.2250738585072014", "1.1754944"]:
            cases.append(mantissa + "e" + str(k))
    # Many leading zeros, trailing zeros and signs.
    cases += ["0", "-0", "0.0", "000123.4500", "-0.000000000000000000000000001", "0.1e1", "100e-2",
              "1e0", "1e+0", "-1e-0", "0.000000000000000000000000000000000000001e40"]
    seen, out = set(), []
    for text in cases:
        if text not in seen:
            seen.add(text)
            out.append(text)
    return out


# ---------------------------------------------------------------- writing

def neper_string(lines):
    body = "".join(line + "\\n" for line in lines)
    assert '"' not in body and "\\x" not in body
    return '"' + body + '"'


def chunks(name, lines, size=600):
    out = []
    for i in range(0, len(lines), size):
        part = lines[i:i + size]
        out.append("fn %s_%d() -> str { ret %s }\n" % (name, i // size, neper_string(part)))
    count = (len(lines) + size - 1) // size
    return out, count


def main():
    format64 = ["%016x %s" % (b, push(b, 64)) for b in format_cases64()]
    format32 = ["%08x %s" % (b, push(b, 32)) for b in format_cases32()]
    parse64, parse32 = [], []
    for text in parse_cases(64):
        bits = parse(text, 64)
        parse64.append(("%016x" % bits if bits is not None else "!") + " " + text)
    for text in parse_cases(32):
        bits = parse(text, 32)
        parse32.append(("%08x" % bits if bits is not None else "!") + " " + text)
    parts = ["// Generated by ../vectors.py; do not edit. Each chunk is `bits text` lines: for the\n"
             "// formats, what push writes for those bits; for the parses, the bits a parse of\n"
             "// the text answers, or `!` for BadNumber.\n\n"]
    counts = {}
    for name, lines in [("format64", format64), ("format32", format32), ("parse64", parse64), ("parse32", parse32)]:
        text, count = chunks(name, lines)
        parts += text
        counts[name] = count
        parts.append("\n")
    # One dispatcher per table, so the fixture walks chunks by number.
    for name, count in counts.items():
        parts.append("fn %s(i: usize) -> str {\n" % name)
        for i in range(count):
            parts.append("    if i == %dusize { ret %s_%d() }\n" % (i, name, i))
        parts.append('    ret ""\n}\n\n')
    for name, count in counts.items():
        parts.append("const %s_CHUNKS: usize = %dusize\n" % (name.upper(), count))
    (HERE / "src" / "vectors.e").write_text("".join(parts), encoding="utf-8", newline="\n")
    print({k: len(v) for k, v in [("format64", format64), ("format32", format32), ("parse64", parse64), ("parse32", parse32)]})


if __name__ == "__main__":
    main()
