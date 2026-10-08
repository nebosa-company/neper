"""Write tests/selfhost/fixtures/link/crypto_otp/src/main.e (L078, D2268).

  python scripts/otp_reference.py

e.crypto.otp against Python's hmac/hashlib and the published vectors. The generator first asserts its own
HOTP/TOTP implementation reproduces RFC 4226 appendix D (counters 0 to 9, plus the intermediate HMAC,
offset and 31-bit truncation for counter 0) and RFC 6238 appendix B (SHA-1, SHA-256 and SHA-512 at the six
published times), so the reference is byte-exact before it produces anything. The fixture then replays those
vectors and 270 seeded cases (three algorithms, keys of 1 to 200 bytes so the long-key hashing path runs,
digit counts 6 to 9, counters up to 2^64 - 1), the look-ahead and skew verification windows, the
zero-padded formatter, and every refusal. A mismatch prints its table and index and exits 1.
"""
import hashlib
import hmac
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
rng = np.random.default_rng(20261020)
ALGS = {'Sha1': hashlib.sha1, 'Sha256': hashlib.sha256, 'Sha512': hashlib.sha512}


def hotp_full(alg, key, counter, digits):
    mac = hmac.new(key, counter.to_bytes(8, 'big'), ALGS[alg]).digest()
    offset = mac[-1] & 0xF
    p = int.from_bytes(mac[offset:offset + 4], 'big') & 0x7FFFFFFF
    return mac, offset, p, p % 10 ** digits


def hotp(alg, key, counter, digits):
    return hotp_full(alg, key, counter, digits)[3]


def totp(alg, key, seconds, start, period, digits):
    return hotp(alg, key, (seconds - start) // period, digits)


# ---- published vectors, asserted before anything is generated ----
rfc_key = b'12345678901234567890'
rfc4226 = [755224, 287082, 359152, 969429, 338314, 254676, 287922, 162583, 399871, 520489]
for c, want in enumerate(rfc4226):
    assert hotp('Sha1', rfc_key, c, 6) == want
mac0, off0, p0, _ = hotp_full('Sha1', rfc_key, 0, 6)
assert mac0.hex() == 'cc93cf18508d94934c64b65d8ba7667fb7cde4b0' and off0 == 0 and p0 == 0x4c93cf18 == 1284755224
assert hotp_full('Sha1', rfc_key, 0, 8)[3] == 84755224
keys6238 = {'Sha1': b'12345678901234567890', 'Sha256': b'12345678901234567890123456789012',
            'Sha512': b'1234567890123456789012345678901234567890123456789012345678901234'}
times = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]
rfc6238 = {
    'Sha1': [94287082, 7081804, 14050471, 89005924, 69279037, 65353130],
    'Sha256': [46119246, 68084774, 67062674, 91819424, 90698825, 77737706],
    'Sha512': [90693936, 25091201, 99943326, 93441116, 38618901, 47863826],
}
for alg in ALGS:
    for t, want in zip(times, rfc6238[alg]):
        assert totp(alg, keys6238[alg], t, 0, 30, 8) == want, (alg, t)

lines = []


def quote(s):
    return '"' + s + '"'


def alg_ref(a):
    return '.' + a


lines.append('    var tag_buffer: [9]u8 = zero')

# RFC 4226 table (SHA-1, six digits, counters 0-9) and the eight-digit counter-0 value
lines.append('    let rfc_key = "12345678901234567890"')
for c, want in enumerate(rfc4226):
    lines.append('    let (rfc4226_%d, rfc4226_%d_error) = otp.hotp(.Sha1, rfc_key, %du64, 6u32)' % (c, c, c))
    lines.append('    if rfc4226_%d_error != ok || rfc4226_%d != %du32 { try report("rfc4226", %dusize) }' % (c, c, want, c))
lines.append('    let (rfc_eight, rfc_eight_error) = otp.hotp(.Sha1, rfc_key, 0u64, 8u32)')
lines.append('    if rfc_eight_error != ok || rfc_eight != 84755224u32 { try report("rfc4226-eight", 0usize) }')

# RFC 6238 table
k = 0
for alg in ALGS:
    key = keys6238[alg]
    lines.append('    let rfc6238_key_%s = "%s"' % (alg, key.decode()))
    for t, want in zip(times, rfc6238[alg]):
        lines.append('    let (rfc6238_%d, rfc6238_%d_error) = otp.totp(.%s, rfc6238_key_%s, %du64, 0u64, 30u32, 8u32)' % (k, k, alg, alg, t))
        lines.append('    if rfc6238_%d_error != ok || rfc6238_%d != %du32 { try report("rfc6238", %dusize) }' % (k, k, want, k))
        k += 1

# seeded cases: key, counter, digits, expected, per algorithm
CHARS = list('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:,.<>/?|~')
for alg in ALGS:
    rows = []
    for i in range(90):
        length = [1, 20, 32, 63, 64, 65, 100, 127, 128, 129, 130, 200][i % 12] if i < 36 else int(rng.integers(1, 140))
        key = ''.join(CHARS[int(rng.integers(0, len(CHARS)))] for _ in range(length))
        counter = [0, 1, 2 ** 32 - 1, 2 ** 32, 2 ** 63, 2 ** 64 - 1][i % 6] if i < 18 else int(rng.integers(0, 2 ** 63)) * 2 + int(rng.integers(0, 2))
        digits = 6 + (i % 4)
        rows.append((key, counter, digits, hotp(alg, key.encode(), counter, digits)))
    name = 'seeded_%s' % alg
    lines.append('    let %s_keys = [%d]str{ %s }' % (name, len(rows), ', '.join(quote(r[0]) for r in rows)))
    lines.append('    let %s_counters = [%d]u64{ %s }' % (name, len(rows), ', '.join('%du64' % r[1] for r in rows)))
    lines.append('    let %s_digits = [%d]u32{ %s }' % (name, len(rows), ', '.join('%du32' % r[2] for r in rows)))
    lines.append('    let %s_want = [%d]u32{ %s }' % (name, len(rows), ', '.join('%du32' % r[3] for r in rows)))
    lines.append('    var %s_i = 0usize' % name)
    lines.append('    while %s_i < %d {' % (name, len(rows)))
    lines.append('        let (%s_got, %s_error) = otp.hotp(.%s, %s_keys[%s_i], %s_counters[%s_i], %s_digits[%s_i])' % (name, name, alg, name, name, name, name, name, name))
    lines.append('        if %s_error != ok || %s_got != %s_want[%s_i] { try report("%s", %s_i) }' % (name, name, name, name, name, name))
    lines.append('        %s_i += 1usize' % name)
    lines.append('    }')

# totp with a non-zero T0 and other periods
t_rows = []
for i in range(40):
    alg = list(ALGS)[i % 3]
    key = ''.join(CHARS[int(rng.integers(0, len(CHARS)))] for _ in range(int(rng.integers(5, 70))))
    start = int(rng.integers(0, 1000))
    period = [30, 60, 15, 1, 90][i % 5]
    seconds = start + int(rng.integers(0, 4_000_000_000))
    digits = 6 + (i % 4)
    t_rows.append((alg, key, seconds, start, period, digits, totp(alg, key.encode(), seconds, start, period, digits)))
lines.append('    let totp_keys = [%d]str{ %s }' % (len(t_rows), ', '.join(quote(r[1]) for r in t_rows)))
lines.append('    let totp_seconds = [%d]u64{ %s }' % (len(t_rows), ', '.join('%du64' % r[2] for r in t_rows)))
lines.append('    let totp_starts = [%d]u64{ %s }' % (len(t_rows), ', '.join('%du64' % r[3] for r in t_rows)))
lines.append('    let totp_periods = [%d]u32{ %s }' % (len(t_rows), ', '.join('%du32' % r[4] for r in t_rows)))
lines.append('    let totp_digits = [%d]u32{ %s }' % (len(t_rows), ', '.join('%du32' % r[5] for r in t_rows)))
lines.append('    let totp_want = [%d]u32{ %s }' % (len(t_rows), ', '.join('%du32' % r[6] for r in t_rows)))
lines.append('    var totp_i = 0usize')
lines.append('    while totp_i < %d {' % len(t_rows))
for a_i, alg in enumerate(ALGS):
    lines.append('        if totp_i %% 3usize == %dusize {' % a_i)
    lines.append('            let (totp_got_%d, totp_error_%d) = otp.totp(.%s, totp_keys[totp_i], totp_seconds[totp_i], totp_starts[totp_i], totp_periods[totp_i], totp_digits[totp_i])' % (a_i, a_i, alg))
    lines.append('            if totp_error_%d != ok || totp_got_%d != totp_want[totp_i] { try report("totp", totp_i) }' % (a_i, a_i))
    lines.append('        }')
lines.append('        totp_i += 1usize')
lines.append('    }')

# verification windows
key = 'verification-key-123'
base = 1000
lines.append('    let verify_key = "%s"' % key)
v = {c: hotp('Sha1', key.encode(), c, 6) for c in range(base - 2, base + 9)}
assert len({v[base + i] for i in range(0, 8)}) == 8  # no accidental collisions in the window
lines.append('    let (m0, f0, e0) = otp.verify_hotp(.Sha1, verify_key, %du64, 5u32, 6u32, %du32)' % (base, v[base]))
lines.append('    if e0 != ok || !f0 || m0 != %du64 { try report("verify-hotp", 0usize) }' % base)
lines.append('    let (m3, f3, e3) = otp.verify_hotp(.Sha1, verify_key, %du64, 5u32, 6u32, %du32)' % (base, v[base + 3]))
lines.append('    if e3 != ok || !f3 || m3 != %du64 { try report("verify-hotp", 1usize) }' % (base + 3))
lines.append('    let (m5, f5, e5) = otp.verify_hotp(.Sha1, verify_key, %du64, 5u32, 6u32, %du32)' % (base, v[base + 5]))
lines.append('    if e5 != ok || !f5 || m5 != %du64 { try report("verify-hotp", 2usize) }' % (base + 5))
lines.append('    let (m6, f6, e6) = otp.verify_hotp(.Sha1, verify_key, %du64, 5u32, 6u32, %du32)' % (base, v[base + 6]))
lines.append('    if e6 != ok || f6 || m6 != %du64 { try report("verify-hotp", 3usize) }' % base)
lines.append('    let (mb, fb, eb) = otp.verify_hotp(.Sha1, verify_key, %du64, 5u32, 6u32, %du32)' % (base, v[base - 1]))
lines.append('    if eb != ok || fb { try report("verify-hotp", 4usize) }')
lines.append('    let (mz, fz, ez) = otp.verify_hotp(.Sha1, verify_key, %du64, 0u32, 6u32, %du32)' % (base, v[base + 1]))
lines.append('    if ez != ok || fz { try report("verify-hotp", 5usize) }')
lines.append('    let (mw, fw, ew) = otp.verify_hotp(.Sha1, verify_key, %du64, 0u32, 6u32, %du32)' % (base, v[base]))
lines.append('    if ew != ok || !fw || mw != %du64 { try report("verify-hotp", 6usize) }' % base)
t0, period = 0, 30
now = 1_700_000_000
step = (now - t0) // period
tv = {s: totp('Sha256', key.encode(), t0 + s * period, t0, period, 8) for s in range(step - 3, step + 4)}
assert len(set(tv.values())) == len(tv)
lines.append('    let (tm0, tf0, te0) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 1u32, %du32)' % (now, tv[step]))
lines.append('    if te0 != ok || !tf0 || tm0 != %du64 { try report("verify-totp", 0usize) }' % step)
lines.append('    let (tm1, tf1, te1) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 1u32, %du32)' % (now, tv[step - 1]))
lines.append('    if te1 != ok || !tf1 || tm1 != %du64 { try report("verify-totp", 1usize) }' % (step - 1))
lines.append('    let (tm2, tf2, te2) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 1u32, %du32)' % (now, tv[step + 1]))
lines.append('    if te2 != ok || !tf2 || tm2 != %du64 { try report("verify-totp", 2usize) }' % (step + 1))
lines.append('    let (tm3, tf3, te3) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 1u32, %du32)' % (now, tv[step + 2]))
lines.append('    if te3 != ok || tf3 || tm3 != %du64 { try report("verify-totp", 3usize) }' % step)
lines.append('    let (tm4, tf4, te4) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 3u32, %du32)' % (now, tv[step - 3]))
lines.append('    if te4 != ok || !tf4 || tm4 != %du64 { try report("verify-totp", 4usize) }' % (step - 3))
lines.append('    let (tm5, tf5, te5) = otp.verify_totp(.Sha256, verify_key, %du64, 0u64, 30u32, 8u32, 0u32, %du32)' % (now, tv[step - 1]))
lines.append('    if te5 != ok || tf5 { try report("verify-totp", 5usize) }')
# skew larger than the step clamps at step 0
early = {s: totp('Sha1', key.encode(), s * 30, 0, 30, 6) for s in range(0, 5)}
lines.append('    let (tm6, tf6, te6) = otp.verify_totp(.Sha1, verify_key, 10u64, 0u64, 30u32, 6u32, 3u32, %du32)' % early[3])
lines.append('    if te6 != ok || !tf6 || tm6 != 3u64 { try report("verify-totp", 6usize) }')
lines.append('    let (tm7, tf7, te7) = otp.verify_totp(.Sha1, verify_key, 10u64, 0u64, 30u32, 6u32, 3u32, %du32)' % early[0])
lines.append('    if te7 != ok || !tf7 || tm7 != 0u64 { try report("verify-totp", 7usize) }')
# a non-zero T0 shifts the step
lines.append('    let (tm8, tf8, te8) = otp.verify_totp(.Sha1, verify_key, %du64, 1000u64, 30u32, 6u32, 0u32, %du32)' % (1000 + 30 * 7 + 5, totp('Sha1', key.encode(), 1000 + 30 * 7 + 5, 1000, 30, 6)))
lines.append('    if te8 != ok || !tf8 || tm8 != 7u64 { try report("verify-totp", 8usize) }')

# time_step
lines.append('    let (ts0, ts0_error) = otp.time_step(59u64, 0u64, 30u32)')
lines.append('    let (ts1, ts1_error) = otp.time_step(60u64, 0u64, 30u32)')
lines.append('    let (ts2, ts2_error) = otp.time_step(1059u64, 1000u64, 30u32)')
lines.append('    if ts0_error != ok || ts0 != 1u64 || ts1_error != ok || ts1 != 2u64 || ts2_error != ok || ts2 != 1u64 { try report("time-step", 0usize) }')

# formatter
fmt = [(755224, 6), (7, 6), (0, 6), (0, 9), (84755224, 8), (7081804, 8), (999999999, 9), (5, 1), (123456, 6)]
for i, (code, digits) in enumerate(fmt):
    lines.append('    let (text_%d, text_%d_error) = otp.format(%du32, %du32, tag_buffer[..])' % (i, i, code, digits))
    lines.append('    if text_%d_error != ok || !same(text_%d, "%s") { try report("format", %dusize) }' % (i, i, str(code).zfill(digits), i))

# refusals
lines.append('    let empty_key = ""')
lines.append('    let (_, r0) = otp.hotp(.Sha1, empty_key, 0u64, 6u32)')
lines.append('    let (_, r1) = otp.hotp(.Sha1, rfc_key, 0u64, 5u32)')
lines.append('    let (_, r2) = otp.hotp(.Sha1, rfc_key, 0u64, 10u32)')
lines.append('    let (_, r3) = otp.hotp(.Sha1, rfc_key, 0u64, 0u32)')
lines.append('    let (_, r4) = otp.totp(.Sha256, rfc_key, 100u64, 0u64, 0u32, 6u32)')
lines.append('    let (_, r5) = otp.totp(.Sha256, rfc_key, 5u64, 10u64, 30u32, 6u32)')
lines.append('    let (_, r6) = otp.totp(.Sha512, empty_key, 100u64, 0u64, 30u32, 6u32)')
lines.append('    let (_, r7) = otp.time_step(1u64, 0u64, 0u32)')
lines.append('    let (_, r8) = otp.time_step(1u64, 2u64, 30u32)')
lines.append('    let (_, _, r9) = otp.verify_hotp(.Sha1, empty_key, 0u64, 3u32, 6u32, 1u32)')
lines.append('    let (_, _, r10) = otp.verify_hotp(.Sha1, rfc_key, 0u64, 3u32, 10u32, 1u32)')
lines.append('    let (_, _, r11) = otp.verify_totp(.Sha1, rfc_key, 100u64, 0u64, 0u32, 6u32, 1u32, 1u32)')
lines.append('    let (_, _, r12) = otp.verify_totp(.Sha1, rfc_key, 5u64, 10u64, 30u32, 6u32, 1u32, 1u32)')
lines.append('    let (_, _, r13) = otp.verify_totp(.Sha1, empty_key, 100u64, 0u64, 30u32, 6u32, 1u32, 1u32)')
lines.append('    let (_, f1_error) = otp.format(1000000u32, 6u32, tag_buffer[..])')
lines.append('    let (_, f2_error) = otp.format(5u32, 0u32, tag_buffer[..])')
lines.append('    let (_, f3_error) = otp.format(5u32, 10u32, tag_buffer[..])')
lines.append('    let (_, f4_error) = otp.format(5u32, 6u32, tag_buffer[..5usize])')
for i in range(14):
    lines.append('    if r%d != otp.Invalid { try report("refusal", %dusize) }' % (i, i))
for i, nme in enumerate(['f1_error', 'f2_error', 'f3_error', 'f4_error']):
    lines.append('    if %s != otp.Invalid { try report("format-refusal", %dusize) }' % (nme, i))
# a counter at the top of the range still works (no overflow in the 8-byte encoding), and window+counter wrap is the caller's business
lines.append('    let (top, top_error) = otp.hotp(.Sha1, rfc_key, 18446744073709551615u64, 6u32)')
lines.append('    if top_error != ok || top != %du32 { try report("top-counter", 0usize) }' % hotp('Sha1', rfc_key, 2 ** 64 - 1, 6))

body = '\n'.join(lines)
source = '''// e.crypto.otp against RFC 4226 appendix D, RFC 6238 appendix B and Python's hmac/hashlib (L078, D2268;
// scripts/otp_reference.py writes this file): the published vectors for SHA-1, SHA-256 and SHA-512, 270
// seeded HOTP cases with keys of 1 to 200 bytes, 40 TOTP cases with other periods and T0, the look-ahead and
// skew windows, the zero-padded formatter, and every refusal. A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.crypto.otp as otp

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 0u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("otp mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i])..usize(digits[i]) + 1usize])
    }
    try io.print("\\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("crypto otp ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'crypto_otp' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote crypto_otp: RFC vectors verified; 270 seeded + 40 totp cases')
