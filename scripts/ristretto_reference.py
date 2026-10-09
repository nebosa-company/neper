"""Independent reference for e.crypto.ristretto (RFC 9496) and the generator of its fixture.

  python scripts/ristretto_reference.py            check the reference against RFC 9496 and write the fixture
  python scripts/ristretto_reference.py --check    only check the reference

The reference is plain Python integers following RFC 9496 sections 4.2-4.3 and appendix A: field and
Edwards arithmetic over 2^255 - 19, decode, encode, the Elligator map and the 64-byte derivation. It shares
nothing with lib/e/crypto/sign.e's limb arithmetic. It first checks itself against RFC 9496's published
encodings of the multiples of the generator and its bad encodings, then writes
tests/selfhost/fixtures/link/crypto_ristretto/src/main.e from scripts/ristretto_fixture_template.e with the
vectors substituted: encodings of multiples, valid and invalid decodes, the MAP of 32-byte strings, the
derivation of 64-byte strings, scalar multiplication, addition and subtraction.
"""
import hashlib
import pathlib
import random
import sys

P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = (-121665 * pow(121666, P - 2, P)) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)
INVSQRT_A_MINUS_D = None  # filled below


def inv(x):
    return pow(x, P - 2, P)


def is_neg(x):
    return (x % P) & 1


def cabs(x):
    x %= P
    return (-x) % P if x & 1 else x


def sqrt_ratio(u, v):
    u %= P
    v %= P
    v3 = v * v % P * v % P
    v7 = v3 * v3 % P * v % P
    r = u * v3 % P * pow(u * v7 % P, (P - 5) // 8, P) % P
    check = v * r % P * r % P
    correct = check == u
    flipped = check == (-u) % P
    flipped_i = check == (-u * SQRT_M1) % P
    if flipped or flipped_i:
        r = SQRT_M1 * r % P
    r = cabs(r)
    return (correct or flipped), r


# The constants of RFC 9496 section 4.1, derived (a = -1) and checked against the published values.
SQRT_AD_MINUS_ONE = 25063068953384623474111414158702152701244531502492656460079210482610430750235
assert SQRT_AD_MINUS_ONE * SQRT_AD_MINUS_ONE % P == (-D - 1) % P
ok, root = sqrt_ratio(1, (-1 - D) % P)
INVSQRT_A_MINUS_D = root  # 1/sqrt(a - d) with a = -1: a - d = -1 - d
ONE_MINUS_D_SQ = (1 - D * D) % P
D_MINUS_ONE_SQ = (D - 1) ** 2 % P
assert INVSQRT_A_MINUS_D == 54469307008909316920995813868745141605393597292927456921205312896311721017578
assert ONE_MINUS_D_SQ == 1159843021668779879193775521855586647937357759715417654439879720876111806838
assert D_MINUS_ONE_SQ == 40440834346308536858101042469323190826248399146238708352240133220865137265952


def decode(data):
    if len(data) != 32:
        return None
    s = int.from_bytes(data, 'little')
    if s >= P or s & 1:
        return None
    ss = s * s % P
    u1 = (1 - ss) % P
    u2 = (1 + ss) % P
    u2_sqr = u2 * u2 % P
    v = (-(D * u1 % P * u1) - u2_sqr) % P
    was_square, invsqrt = sqrt_ratio(1, v * u2_sqr % P)
    den_x = invsqrt * u2 % P
    den_y = invsqrt * den_x % P * v % P
    x = cabs(2 * s * den_x)
    y = u1 * den_y % P
    t = x * y % P
    if not was_square or is_neg(t) or y == 0:
        return None
    return (x, y, 1, t)


def encode(pt):
    x0, y0, z0, t0 = pt
    u1 = (z0 + y0) * (z0 - y0) % P
    u2 = x0 * y0 % P
    _, invsqrt = sqrt_ratio(1, u1 * u2 % P * u2 % P)
    den1 = invsqrt * u1 % P
    den2 = invsqrt * u2 % P
    z_inv = den1 * den2 % P * t0 % P
    ix0 = x0 * SQRT_M1 % P
    iy0 = y0 * SQRT_M1 % P
    enchanted = den1 * INVSQRT_A_MINUS_D % P
    if is_neg(t0 * z_inv % P):
        x, y, den_inv = iy0, ix0, enchanted
    else:
        x, y, den_inv = x0, y0, den2
    if is_neg(x * z_inv % P):
        y = (-y) % P
    s = cabs(den_inv * (z0 - y) % P)
    return s.to_bytes(32, 'little')


def edwards_add(p1, p2):
    x1, y1, z1, t1 = p1
    x2, y2, z2, t2 = p2
    a = (y1 - x1) * (y2 - x2) % P
    b = (y1 + x1) * (y2 + x2) % P
    c = t1 * 2 * D % P * t2 % P
    dd = z1 * 2 * z2 % P
    e, f, g, h = (b - a) % P, (dd - c) % P, (dd + c) % P, (b + a) % P
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def neg(pt):
    return ((-pt[0]) % P, pt[1], pt[2], (-pt[3]) % P)


IDENTITY = (0, 1, 1, 0)
BASE_Y = 4 * inv(5) % P
_, _bx = sqrt_ratio((BASE_Y * BASE_Y - 1) % P, (D * BASE_Y * BASE_Y + 1) % P)
BASE = (_bx if not _bx & 1 else (-_bx) % P, BASE_Y, 1, 0)
BASE = (BASE[0], BASE[1], 1, BASE[0] * BASE[1] % P)


def scalar_mul(k, pt):
    result = IDENTITY
    addend = pt
    while k:
        if k & 1:
            result = edwards_add(result, addend)
        addend = edwards_add(addend, addend)
        k >>= 1
    return result


def mapping(data):
    t = int.from_bytes(data, 'little') & ((1 << 255) - 1)
    t %= P
    r = SQRT_M1 * t % P * t % P
    u = (r + 1) * ONE_MINUS_D_SQ % P
    v = (-1 - r * D) % P * ((r + D) % P) % P
    was_square, s = sqrt_ratio(u, v)
    s_prime = (-cabs(s * t % P)) % P
    if not was_square:
        s = s_prime
    c = (-1) % P if was_square else r
    n = (c * ((r - 1) % P) % P * D_MINUS_ONE_SQ - v) % P
    w0 = 2 * s * v % P
    w1 = n * SQRT_AD_MINUS_ONE % P
    w2 = (1 - s * s) % P
    w3 = (1 + s * s) % P
    return (w0 * w3 % P, w2 * w1 % P, w1 * w3 % P, w0 * w2 % P)


def derive(data):
    return edwards_add(mapping(data[:32]), mapping(data[32:]))


# RFC 9496 appendix A.1: encodings of the multiples 0..5 of the generator, and some bad encodings.
RFC_MULTIPLES = [
    '0000000000000000000000000000000000000000000000000000000000000000',
    'e2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76',
    '6a493210f7499cd17fecb510ae0cea23a110e8d5b901f8acadd3095c73a3b919',
    '94741f5d5d52755ece4f23f044ee27d5d1ea1e2bd196b462166b16152a9d0259',
    'da80862773358b466ffadfe0b3293ab3d9fd53c5ea6c955358f568322daf6a57',
    'e882b131016b52c1d3337080187cf768423efccbb517bb495ab812c4160ff44e',
]
RFC_BAD = [
    # non-canonical field encodings
    '00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'f3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    # negative field elements
    '0100000000000000000000000000000000000000000000000000000000000000',
    '01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'ed57ffd8c914fb201471d1c3d245ce3c746fcbe63a3679d51b6a516c77d7f060',
    # non-square x^2
    '26948d35ca62e643e26a83177332e6b6afeb9d08e4268b650f1f5bbd8d81d371',
    '4eac077a713c57b4f4397629a4145982c661f48044dd3f96427d40b147d9742f',
    'de6a7b00deadc788eb6b6c8d20c0ae96c2f2019078fa604fee5b87d6e989ad7b',
    # negative xy value
    '2a292df7e32cababbd9de088d1d1abec9fc0440f637ed2fba145094dc14bea08',
    '2a292df7e32cababbd9de088d1d1abec9fc0440f637ed2fba145094dc14bea08'[:-2] + '09',
    # s = -1, which causes y = 0
    'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
]


def check_against_rfc():
    for k, expected in enumerate(RFC_MULTIPLES):
        got = encode(scalar_mul(k, BASE)).hex()
        assert got == expected, (k, got, expected)
        point = decode(bytes.fromhex(expected))
        assert point is not None and encode(point).hex() == expected, k
    for bad in RFC_BAD:
        assert decode(bytes.fromhex(bad)) is None, bad
    assert encode(scalar_mul(L, BASE)).hex() == RFC_MULTIPLES[0]


def hexs(data):
    return data.hex()


def build():
    rng = random.Random(0x9496)
    lines = []

    def add(kind, *fields):
        lines.append(kind + ' ' + ' '.join(fields))

    # B: the multiples 0..15 of the generator.
    for k in range(16):
        add('B', str(k), hexs(encode(scalar_mul(k, BASE))))
    # V: decoding. The RFC's bad encodings, then random strings and encodings of random points (valid), each
    # with its verdict; a valid one must encode back to itself.
    pool = [bytes.fromhex(b) for b in RFC_BAD]
    for k in range(16):
        pool.append(bytes.fromhex(RFC_MULTIPLES[k % 6]) if k < 6 else encode(scalar_mul(rng.getrandbits(250), BASE)))
    for _ in range(40):
        pool.append(encode(scalar_mul(rng.getrandbits(250) + 1, BASE)))
    for _ in range(60):
        pool.append(bytes(rng.getrandbits(8) for _ in range(32)))
    for _ in range(20):
        # s even, canonical, otherwise random: about half are on the curve
        s = rng.getrandbits(254) & ~1
        pool.append(s.to_bytes(32, 'little'))
    for data in pool:
        point = decode(data)
        if point is None:
            add('V', hexs(data), '0')
        else:
            assert encode(point) == data
            add('V', hexs(data), '1')
    # M: the Elligator map of random 32-byte strings (the top bit set in some: it is masked).
    for _ in range(100):
        data = bytes(rng.getrandbits(8) for _ in range(32))
        add('M', hexs(data), hexs(encode(mapping(data))))
    # D: the 64-byte derivation; two from SHA-512 of labels, the rest random.
    for label in (b'Ristretto is traditionally a short shorter', b'neper e.crypto.ristretto'):
        data = hashlib.sha512(label).digest()
        add('D', hexs(data), hexs(encode(derive(data))))
    for _ in range(60):
        data = bytes(rng.getrandbits(8) for _ in range(64))
        add('D', hexs(data), hexs(encode(derive(data))))
    # S: a scalar (32 bytes, not reduced: the library reduces mod l) times a point.
    for _ in range(40):
        k = rng.getrandbits(256)
        pt = scalar_mul(rng.getrandbits(250) + 1, BASE)
        add('S', hexs(k.to_bytes(32, 'little')), hexs(encode(pt)), hexs(encode(scalar_mul(k % L, pt))))
    add('S', hexs((L).to_bytes(32, 'little')), hexs(encode(BASE)), hexs(encode(IDENTITY)))
    add('S', hexs((L - 1).to_bytes(32, 'little')), hexs(encode(BASE)), hexs(encode(neg(BASE))))
    # A: addition and subtraction of two points.
    for _ in range(40):
        p1 = scalar_mul(rng.getrandbits(250), BASE)
        p2 = scalar_mul(rng.getrandbits(250), BASE)
        add('A', hexs(encode(p1)), hexs(encode(p2)), hexs(encode(edwards_add(p1, p2))), hexs(encode(edwards_add(p1, neg(p2)))))
    return lines


def chunked(lines, per):
    parts = []
    for i in range(0, len(lines), per):
        parts.append('"' + '\\n'.join(lines[i:i + per]) + '\\n"')
    return parts


def main():
    check_against_rfc()
    print('reference agrees with RFC 9496: multiples 0..5, 13 bad encodings, the group order')
    if '--check' in sys.argv:
        return
    here = pathlib.Path(__file__).resolve().parent
    template = (here / 'ristretto_fixture_template.e').read_text(encoding='utf-8')
    lines = build()
    parts = chunked(lines, 60)
    funcs = []
    for i, part in enumerate(parts):
        funcs.append('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, part))
    calls = ''.join('    let verdict_%d = run(vectors_%d(), ladder[0..])\n    if verdict_%d != 0u8 { os.exit(i32(verdict_%d)) }\n' % (i, i, i, i) for i in range(len(parts)))
    out = template.replace('//__VECTOR_FUNCTIONS__\n', '\n'.join(funcs)).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'crypto_ristretto' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', target.relative_to(here.parent), len(lines), 'cases in', len(parts), 'chunks')


main()
