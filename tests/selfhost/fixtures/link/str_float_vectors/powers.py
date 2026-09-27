"""Write the power-of-five tables into lib/e/str.e (D1593).

    python tests/selfhost/fixtures/link/str_float_vectors/powers.py

- `powers` in parse_f64, Eisel-Lemire's table: entry q (q in [-342, 308]) is the top 128
  bits of 5^q, truncated for q >= 0, and for q < 0 the top bits of 2^k / 5^-q rounded up --
  the table of Lemire's "Number Parsing at a Gigabyte per Second" and fast_float.
- `ryu_inverse` and `ryu_forward` in push_f64, Ryu's d2s tables: 2^(len(5^i) - 1 + 125) /
  5^i + 1 for i in [0, 341], and 5^i scaled to 125 significant bits for i in [0, 325].
- `ryu_inverse` and `ryu_forward` in push_f32, Ryu's f2s tables: the same with 59 bits for
  i in [0, 30] and 61 bits for i in [0, 46].

128-bit entries are 32 lowercase hex digits and 64-bit ones 16, high digits first. Each
`let NAME = ...` line is rewritten in place, from its placeholder or its previous literal.
"""
import re
from pathlib import Path

STR_E = Path(__file__).resolve().parents[5] / "lib" / "e" / "str.e"


def entry(q):
    if q < 0:
        power5 = 5 ** -q
        # The least z with 2^z >= 5^-q.
        z = (power5 - 1).bit_length()
        if q >= -27:
            c = 2 ** (z + 127) // power5 + 1
        else:
            c = 2 ** (2 * z + 128) // power5 + 1
            while c >= 1 << 128:
                c //= 2
        return c
    power5 = 5 ** q
    while power5 < 1 << 127:
        power5 *= 2
    while power5 >= 1 << 128:
        power5 //= 2
    return power5


def ryu_inverse(i, bitcount):
    power5 = 5 ** i
    return (1 << (power5.bit_length() - 1 + bitcount)) // power5 + 1


def ryu_forward(i, bitcount):
    power5 = 5 ** i
    shift = power5.bit_length() - bitcount
    return power5 >> shift if shift >= 0 else power5 << -shift


def literal(values, digits):
    for v in values:
        assert v < 1 << (4 * digits), v
    return '"' + "".join("%0*x" % (digits, v) for v in values) + '"'


def fill(text, function, name, value):
    """Replace `let NAME = ...` inside `fn FUNCTION(` with `value`."""
    start = text.index("\nfn %s(" % function)
    end = text.index("\n}\n", start)
    body = text[start:end]
    pattern = re.compile(r'(\n    +let %s = )(?:[A-Z0-9_]+|"[0-9a-f]*")' % name)
    assert len(pattern.findall(body)) == 1, (function, name)
    body = pattern.sub(lambda m: m.group(1) + value, body)
    return text[:start] + body + text[end:]


def main():
    text = STR_E.read_text(encoding="utf-8")
    text = fill(text, "parse_f64", "powers", literal([entry(q) for q in range(-342, 309)], 32))
    text = fill(text, "push_f64", "ryu_inverse", literal([ryu_inverse(i, 125) for i in range(342)], 32))
    text = fill(text, "push_f64", "ryu_forward", literal([ryu_forward(i, 125) for i in range(326)], 32))
    text = fill(text, "push_f32", "ryu_inverse", literal([ryu_inverse(i, 59) for i in range(31)], 16))
    text = fill(text, "push_f32", "ryu_forward", literal([ryu_forward(i, 61) for i in range(47)], 16))
    STR_E.write_text(text, encoding="utf-8", newline="\n")
    print("wrote the tables")


if __name__ == "__main__":
    main()
