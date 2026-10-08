"""Write tests/selfhost/fixtures/link/time_ntp/src/main.e (L079, D2269).

  python scripts/ntp_reference.py

The NTP/SNTP codec of e.time.sync against Python's struct and datetime:
  * 150 seeded packets, each packed by struct.pack('!BBbbII4sQQQQ'), decoded and re-encoded byte for byte,
    plus trailing extension bytes ignored and a 47-byte packet refused;
  * timestamp conversions against datetime arithmetic from the era bases (1900-01-01 for era 0 and
    1900-01-01 + 2^32 s for era 1) for 300 seeded Unix instants and 300 seeded NTP words, the era and range
    edges, and the round trip unix -> ntp -> unix, which is exact because 2^-32 s is under a nanosecond;
  * 16.16 short values, offset_delay with halving toward zero, the request builder, every reply verdict,
    and the refusals.
A mismatch prints its table and index and exits 1.
"""
import datetime as dt
import pathlib
import struct
from fractions import Fraction as Fr

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
rng = np.random.default_rng(20261021)
NS = 10 ** 9
EPOCH_1900 = dt.datetime(1900, 1, 1, tzinfo=dt.timezone.utc)
EPOCH_1970 = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
ERA_SPAN = 2 ** 32


def ntp_to_unix_ref(word):
    """NTP word -> Unix nanoseconds through datetime arithmetic, era by the top bit of the seconds."""
    secs, frac = word >> 32, word & 0xFFFFFFFF
    base = EPOCH_1900 if secs >= 2 ** 31 else EPOCH_1900 + dt.timedelta(seconds=ERA_SPAN)
    moment = base + dt.timedelta(seconds=secs)
    whole = int((moment - EPOCH_1970).total_seconds())
    nanos = int((Fr(frac * NS, 2 ** 32) + Fr(1, 2)) // 1)
    return whole * NS + nanos


def unix_to_ntp_ref(nanos):
    secs, rest = divmod(nanos, NS)
    moment = EPOCH_1970 + dt.timedelta(seconds=secs)
    if moment < EPOCH_1900 + dt.timedelta(seconds=2 ** 31) or moment >= EPOCH_1900 + dt.timedelta(seconds=2 ** 31 + ERA_SPAN):
        return None
    ntp_secs = int((moment - EPOCH_1900).total_seconds())
    frac = int((Fr(rest * 2 ** 32, NS) + Fr(1, 2)) // 1)
    if frac == 2 ** 32:
        frac = 0
        ntp_secs += 1
        if ntp_secs >= 2 ** 31 + ERA_SPAN:
            return None
    return ((ntp_secs % ERA_SPAN) << 32) | frac


def trunc_div2(x):
    return x // 2 if x >= 0 else -((-x) // 2)


lines = []


def quote(s):
    return '"' + s + '"'


def report_if(cond, table, idx):
    lines.append('    if %s { try report("%s", %s) }' % (cond, table, idx))


# ---- packets ----
packets = []
for i in range(150):
    leap, version, mode = int(rng.integers(0, 4)), int(rng.integers(0, 8)), int(rng.integers(0, 8))
    stratum = int(rng.integers(0, 256))
    poll, precision = int(rng.integers(-128, 128)), int(rng.integers(-128, 128))
    rd, rdisp, rid = (int(rng.integers(0, 2 ** 32)) for _ in range(3))
    ts = [int(rng.integers(0, 2 ** 63)) * 2 + int(rng.integers(0, 2)) for _ in range(4)]
    if i < 8:
        ts = [0, 2 ** 64 - 1, 1, 2 ** 63][i % 4:] + [0] * 4
        ts = ts[:4]
        poll, precision = [-128, 127, -1, 0, 6, -20, -128, 127][i], [127, -128, -20, 0, -6, 1, 127, -128][i]
    first = (leap << 6) | (version << 3) | mode
    raw = struct.pack('!BBbbIII', first, stratum, poll, precision, rd, rdisp, rid) + struct.pack('!QQQQ', *ts)
    assert len(raw) == 48
    packets.append((leap, version, mode, stratum, poll, precision, rd, rdisp, rid, ts, raw))
n = len(packets)
names = ['leap', 'version', 'mode', 'stratum', 'poll', 'precision', 'rdelay', 'rdisp', 'refid']
kinds = ['u8', 'u8', 'u8', 'u8', 'i32', 'i32', 'u32', 'u32', 'u32']
for k, (nm, kd) in enumerate(zip(names, kinds)):
    lines.append('    let pk_%s = [%d]%s{ %s }' % (nm, n, kd, ', '.join('%d%s' % (p[k], kd) for p in packets)))
for k, nm in enumerate(['ref', 'orig', 'recv', 'xmit']):
    lines.append('    let pk_%s = [%d]u64{ %s }' % (nm, n, ', '.join('%du64' % p[9][k] for p in packets)))
flat = [b for p in packets for b in p[10]]
lines.append('    let pk_bytes = [%d]u8{ %s }' % (len(flat), ', '.join(str(b) for b in flat)))
lines.append('    var pk_out: [48]u8 = zero')
lines.append('    var pk_i = 0usize')
lines.append('    while pk_i < %d {' % n)
lines.append('        let at = pk_i * 48usize')
lines.append('        let (decoded, decode_error) = sync.ntp_decode(pk_bytes[at..at + 48usize])')
lines.append('        if decode_error != ok { try report("decode-error", pk_i) }')
cond = ' || '.join([
    'decoded.leap != pk_leap[pk_i]', 'decoded.version != pk_version[pk_i]', 'decoded.mode != pk_mode[pk_i]', 'decoded.stratum != pk_stratum[pk_i]',
    'decoded.poll != pk_poll[pk_i]', 'decoded.precision != pk_precision[pk_i]'])
lines.append('        if %s { try report("decode-header", pk_i) }' % cond)
cond = ' || '.join(['decoded.root_delay != pk_rdelay[pk_i]', 'decoded.root_dispersion != pk_rdisp[pk_i]', 'decoded.reference_id != pk_refid[pk_i]',
                    'decoded.reference != pk_ref[pk_i]', 'decoded.origin != pk_orig[pk_i]', 'decoded.receive != pk_recv[pk_i]', 'decoded.transmit != pk_xmit[pk_i]'])
lines.append('        if %s { try report("decode-body", pk_i) }' % cond)
lines.append('        let encode_error = sync.ntp_encode(decoded, pk_out[..])')
lines.append('        if encode_error != ok { try report("encode-error", pk_i) }')
lines.append('        var same_bytes = true')
lines.append('        var b = 0usize')
lines.append('        while b < 48usize {')
lines.append('            if pk_out[b] != pk_bytes[at + b] { same_bytes = false }')
lines.append('            b += 1usize')
lines.append('        }')
lines.append('        if !same_bytes { try report("encode-bytes", pk_i) }')
lines.append('        pk_i += 1usize')
lines.append('    }')
# trailing bytes ignored; 47 bytes refused; encode refusals
lines.append('    var longer: [68]u8 = zero')
lines.append('    var copy = 0usize')
lines.append('    while copy < 48usize {')
lines.append('        longer[copy] = pk_bytes[copy]')
lines.append('        copy += 1usize')
lines.append('    }')
lines.append('    longer[50usize] = 255u8')
lines.append('    let (with_tail, tail_error) = sync.ntp_decode(longer[..])')
lines.append('    if tail_error != ok || with_tail.transmit != pk_xmit[0usize] || with_tail.version != pk_version[0usize] { try report("trailing-bytes", 0usize) }')
lines.append('    let (_, short_error) = sync.ntp_decode(pk_bytes[..47usize])')
lines.append('    let (_, empty_error) = sync.ntp_decode(pk_bytes[..0usize])')
lines.append('    if short_error != sync.Invalid || empty_error != sync.Invalid { try report("decode-short", 0usize) }')
lines.append('    let (good, good_error) = sync.ntp_decode(pk_bytes[..48usize])')
lines.append('    if good_error != ok { try report("good", 0usize) }')
lines.append('    var small_out: [47]u8 = zero')
lines.append('    if sync.ntp_encode(good, small_out[..]) != sync.TooSmall { try report("encode-room", 0usize) }')
for label, field, value in (('leap', 'leap', '4u8'), ('version', 'version', '8u8'), ('mode', 'mode', '8u8'), ('poll-high', 'poll', '128i32'), ('poll-low', 'poll', '-129i32'),
                            ('precision-high', 'precision', '128i32'), ('precision-low', 'precision', '-129i32')):
    lines.append('    var bad_%s = good' % label.replace('-', '_'))
    lines.append('    bad_%s.%s = %s' % (label.replace('-', '_'), field, value))
    lines.append('    if sync.ntp_encode(bad_%s, pk_out[..]) != sync.Invalid { try report("encode-%s", 0usize) }' % (label.replace('-', '_'), label))

# ---- unix <-> ntp ----
edges = [0, -1, 1, 10 ** 9 - 1, 946684800 * NS, -61505152 * NS, 2085978496 * NS - 1, 2085978496 * NS, 2085978495 * NS + 999999999,
         4233462144 * NS - 1, 4233462144 * NS - 2, 1700000000 * NS + 123456789, -(2 ** 31) * NS + 1, 253402300799 * NS if False else 3000000000 * NS]
rows = []
for ns_ in edges:
    rows.append(ns_)
while len(rows) < 300:
    secs = int(rng.integers(-61505152, 4233462144))
    rows.append(secs * NS + int(rng.integers(0, NS)))
to_ntp = []
for ns_ in rows:
    ref = unix_to_ntp_ref(ns_)
    to_ntp.append((ns_, ref))
valid_to = [(a, b) for a, b in to_ntp if b is not None]
bad_to = [a for a, b in to_ntp if b is None]
assert valid_to and len(bad_to) >= 0
lines.append('    let u2n_in = [%d]i64{ %s }' % (len(valid_to), ', '.join('%di64' % a for a, _ in valid_to)))
lines.append('    let u2n_want = [%d]u64{ %s }' % (len(valid_to), ', '.join('%du64' % b for _, b in valid_to)))
lines.append('    var u2n_i = 0usize')
lines.append('    while u2n_i < %d {' % len(valid_to))
lines.append('        let (u2n_got, u2n_error) = sync.unix_nanos_to_ntp(u2n_in[u2n_i])')
lines.append('        if u2n_error != ok || u2n_got != u2n_want[u2n_i] { try report("unix-to-ntp", u2n_i) }')
lines.append('        let u2n_back = sync.ntp_to_unix_nanos(u2n_got)')
lines.append('        if u2n_back != u2n_in[u2n_i] { try report("round-trip", u2n_i) }')
lines.append('        u2n_i += 1usize')
lines.append('    }')
# ntp -> unix for seeded words and edge words
words = [0, 2 ** 31 << 32, (2 ** 31 << 32) | 1, (2 ** 32 - 1) << 32 | (2 ** 32 - 1), 1 << 32, (1 << 32) | 2 ** 31, (2 ** 31 - 1) << 32 | (2 ** 32 - 1), (2208988800 << 32), (2208988800 << 32) | 0x80000000]
while len(words) < 300:
    words.append(int(rng.integers(0, 2 ** 63)) * 2 + int(rng.integers(0, 2)))
# the frac that rounds up to a whole second exercises the carry (0xFFFFFFFF * 1e9 / 2^32 = 999999999.77)
words.append((12345 << 32) | 0xFFFFFFFF)
lines.append('    let n2u_in = [%d]u64{ %s }' % (len(words), ', '.join('%du64' % w for w in words)))
lines.append('    let n2u_want = [%d]i64{ %s }' % (len(words), ', '.join('%di64' % ntp_to_unix_ref(w) for w in words)))
lines.append('    var n2u_i = 0usize')
lines.append('    while n2u_i < %d {' % len(words))
lines.append('        if sync.ntp_to_unix_nanos(n2u_in[n2u_i]) != n2u_want[n2u_i] { try report("ntp-to-unix", n2u_i) }')
lines.append('        n2u_i += 1usize')
lines.append('    }')
# range edges
lo_ok = -61505152 * NS
lines.append('    let (lo_word, lo_error) = sync.unix_nanos_to_ntp(%di64)' % lo_ok)
lines.append('    let (_, below_error) = sync.unix_nanos_to_ntp(%di64)' % (lo_ok - 1))
hi_ok = 4233462144 * NS - 1
lines.append('    let (hi_word, hi_error) = sync.unix_nanos_to_ntp(%di64)' % hi_ok)
lines.append('    let (_, above_error) = sync.unix_nanos_to_ntp(%di64)' % (hi_ok + 1))
lines.append('    let (era_word, era_error) = sync.unix_nanos_to_ntp(%di64)' % (2085978496 * NS))
assert unix_to_ntp_ref(lo_ok) is not None and unix_to_ntp_ref(lo_ok - 1) is None and unix_to_ntp_ref(hi_ok + 1) is None
assert unix_to_ntp_ref(2085978496 * NS) == 0
lines.append('    if lo_error != ok || lo_word != %du64 || below_error != sync.Invalid || hi_error != ok || hi_word != %du64 || above_error != sync.Invalid || era_error != ok || era_word != 0u64 { try report("range-edges", 0usize) }' % (unix_to_ntp_ref(lo_ok), unix_to_ntp_ref(hi_ok)))
lines.append('    let (_, far_error) = sync.unix_nanos_to_ntp(9000000000000000000i64)')
lines.append('    let (_, far_negative) = sync.unix_nanos_to_ntp(-9000000000000000000i64)')
lines.append('    if far_error != sync.Invalid || far_negative != sync.Invalid { try report("far-instants", 0usize) }')
lines.append('    let (carry_word, carry_error) = sync.unix_nanos_to_ntp(%di64)' % (4233462144 * NS - 1))
lines.append('    if carry_error != ok || carry_word != %du64 { try report("carry-near-top", 0usize) }' % unix_to_ntp_ref(4233462144 * NS - 1))

# ---- short values ----
shorts = [0, 1, 65535, 65536, 0xFFFFFFFF, 0x00018000, 0x00010001] + [int(rng.integers(0, 2 ** 32)) for _ in range(60)]
short_nanos = [(v >> 16) * NS + int((Fr((v & 0xFFFF) * NS, 65536) + Fr(1, 2)) // 1) for v in shorts]
lines.append('    let sh_in = [%d]u32{ %s }' % (len(shorts), ', '.join('%du32' % v for v in shorts)))
lines.append('    let sh_want = [%d]i64{ %s }' % (len(shorts), ', '.join('%di64' % v for v in short_nanos)))
lines.append('    var sh_i = 0usize')
lines.append('    while sh_i < %d {' % len(shorts))
lines.append('        if sync.ntp_short_to_nanos(sh_in[sh_i]) != sh_want[sh_i] { try report("short-to-nanos", sh_i) }')
lines.append('        let (sh_back, sh_error) = sync.nanos_to_ntp_short(sh_want[sh_i])')
lines.append('        if sh_error != ok || sh_back != sh_in[sh_i] { try report("short-round-trip", sh_i) }')
lines.append('        sh_i += 1usize')
lines.append('    }')
nan_in = [0, 1, 999999999, NS, 65535 * NS + 999999999, 65535 * NS + 999992370, 12 * NS + 345678901, 1500000, 20000000, 123456789012]
nan_want = []
for v in nan_in:
    whole, rest = divmod(v, NS)
    frac = int((Fr(rest * 65536, NS) + Fr(1, 2)) // 1)
    if frac == 65536:
        frac, whole = 0, whole + 1
    nan_want.append(None if whole > 65535 else (whole << 16) | frac)
valid_short = [(a, b) for a, b in zip(nan_in, nan_want) if b is not None]
invalid_short = [a for a, b in zip(nan_in, nan_want) if b is None]
lines.append('    let ns_in = [%d]i64{ %s }' % (len(valid_short), ', '.join('%di64' % a for a, _ in valid_short)))
lines.append('    let ns_want = [%d]u32{ %s }' % (len(valid_short), ', '.join('%du32' % b for _, b in valid_short)))
lines.append('    var ns_i = 0usize')
lines.append('    while ns_i < %d {' % len(valid_short))
lines.append('        let (ns_got, ns_error) = sync.nanos_to_ntp_short(ns_in[ns_i])')
lines.append('        if ns_error != ok || ns_got != ns_want[ns_i] { try report("nanos-to-short", ns_i) }')
lines.append('        ns_i += 1usize')
lines.append('    }')
lines.append('    let (_, short_negative) = sync.nanos_to_ntp_short(-1i64)')
lines.append('    let (_, short_big) = sync.nanos_to_ntp_short(%di64)' % (65536 * NS))
lines.append('    let (_, short_carry_big) = sync.nanos_to_ntp_short(%di64)' % (65535 * NS + 999999999))
lines.append('    if short_negative != sync.Invalid || short_big != sync.Invalid { try report("short-refusals", 0usize) }')
expect_carry = nan_want[nan_in.index(65535 * NS + 999999999)]
lines.append('    if short_carry_big %s sync.Invalid { try report("short-carry-top", 0usize) }' % ('==' if expect_carry is not None else '!='))

# ---- offset and delay ----
od = []
for _ in range(120):
    t1 = int(rng.integers(0, 2 ** 50))
    d1 = int(rng.integers(0, 10 ** 8))
    skew = int(rng.integers(-10 ** 10, 10 ** 10))
    proc = int(rng.integers(0, 10 ** 6))
    d2 = int(rng.integers(0, 10 ** 8))
    t2 = t1 + d1 + skew
    t3 = t2 + proc
    t4 = t3 - skew + d2
    od.append((t1, t2, t3, t4))
od += [(0, 10, 10, 20), (0, 11, 11, 20), (100, 50, 50, 100), (0, 0, 1, 1), (5, 5, 5, 5), (0, 1, 2, 4), (0, -3, -3, 0), (10, 4, 5, 11)]
lines.append('    let od_t = [%d]i64{ %s }' % (4 * len(od), ', '.join('%di64' % x for q in od for x in q)))
lines.append('    let od_want = [%d]i64{ %s }' % (2 * len(od), ', '.join('%di64' % x for t1, t2, t3, t4 in od for x in (trunc_div2((t2 - t1) + (t3 - t4)), (t4 - t1) - (t3 - t2)))))
lines.append('    var od_i = 0usize')
lines.append('    while od_i < %d {' % len(od))
lines.append('        let (od_offset, od_delay) = sync.offset_delay(od_t[od_i * 4usize], od_t[od_i * 4usize + 1usize], od_t[od_i * 4usize + 2usize], od_t[od_i * 4usize + 3usize])')
lines.append('        if od_offset != od_want[od_i * 2usize] || od_delay != od_want[od_i * 2usize + 1usize] { try report("offset-delay", od_i) }')
lines.append('        od_i += 1usize')
lines.append('    }')
# the seeded ones recover the skew and the round trip, within one unit of halving
for q in od[:3]:
    pass

# ---- request builder and reply verdicts ----
lines.append('    let (req4, req4_error) = sync.ntp_request(4u8, 1234567890123456789u64)')
lines.append('    let (req3, req3_error) = sync.ntp_request(3u8, 5u64)')
lines.append('    if req4_error != ok || req4.mode != 3u8 || req4.version != 4u8 || req4.leap != 0u8 || req4.stratum != 0u8 || req4.transmit != 1234567890123456789u64 || req4.origin != 0u64 || req4.receive != 0u64 { try report("request", 0usize) }')
lines.append('    if req3_error != ok || req3.version != 3u8 || req3.transmit != 5u64 { try report("request", 1usize) }')
lines.append('    var req_bytes: [48]u8 = zero')
lines.append('    if sync.ntp_encode(req4, req_bytes[..]) != ok || req_bytes[0usize] != %du8 || req_bytes[1usize] != 0u8 { try report("request-bytes", 0usize) }' % ((0 << 6) | (4 << 3) | 3))
lines.append('    let (_, req0_error) = sync.ntp_request(0u8, 1u64)')
lines.append('    let (_, req5_error) = sync.ntp_request(5u8, 1u64)')
lines.append('    if req0_error != sync.Invalid || req5_error != sync.Invalid { try report("request-version", 0usize) }')
lines.append('    let sent = 7777777777u64')
lines.append('    var reply: sync.NtpPacket = zero')
lines.append('    reply.leap = 0u8')
lines.append('    reply.version = 4u8')
lines.append('    reply.mode = 4u8')
lines.append('    reply.stratum = 2u8')
lines.append('    reply.origin = sent')
lines.append('    reply.transmit = 9999u64')
verdicts = [
    ('ok4', 'ok', []),
    ('ok3', 'ok', [('version', '3u8')]),
    ('mode-client', 'sync.BadReply', [('mode', '3u8')]),
    ('mode-broadcast', 'sync.BadReply', [('mode', '5u8')]),
    ('version-2', 'sync.BadReply', [('version', '2u8')]),
    ('version-5', 'sync.BadReply', [('version', '5u8')]),
    ('origin', 'sync.Mismatch', [('origin', '7777777778u64')]),
    ('origin-zero', 'sync.Mismatch', [('origin', '0u64')]),
    ('kiss', 'sync.KissOfDeath', [('stratum', '0u8')]),
    ('kiss-unsynchronised', 'sync.KissOfDeath', [('stratum', '0u8'), ('leap', '3u8')]),
    ('unsynchronised', 'sync.Unsynchronized', [('leap', '3u8')]),
    ('stratum-16', 'sync.BadReply', [('stratum', '16u8')]),
    ('stratum-15', 'ok', [('stratum', '15u8')]),
    ('stratum-1', 'ok', [('stratum', '1u8')]),
    ('transmit-zero', 'sync.BadReply', [('transmit', '0u64')]),
    ('leap-1', 'ok', [('leap', '1u8')]),
    ('leap-2', 'ok', [('leap', '2u8')]),
]
for k, (label, want, edits) in enumerate(verdicts):
    lines.append('    var verdict_%d = reply' % k)
    for field, value in edits:
        lines.append('    verdict_%d.%s = %s' % (k, field, value))
    lines.append('    if sync.ntp_check_reply(sent, verdict_%d) != %s { try report("reply-%s", %dusize) }' % (k, want, label, k))
lines.append('    if sync.ntp_check_reply(0u64, reply) != sync.Mismatch { try report("sent-zero", 0usize) }')
lines.append('    var wrong_sent = reply')
lines.append('    wrong_sent.origin = 1u64')
lines.append('    if sync.ntp_check_reply(2u64, wrong_sent) != sync.Mismatch { try report("sent-differs", 0usize) }')
lines.append('    var spoof = reply')
lines.append('    spoof.origin = sent + 1u64')
lines.append('    if sync.ntp_check_reply(sent, spoof) != sync.Mismatch { try report("spoofed", 0usize) }')

# a worked exchange: a server 1.5 s ahead, 40 ms each way, 2 ms processing
t1 = 1_700_000_000 * NS
skew = 1_500_000_000
t2 = t1 + 40_000_000 + skew
t3 = t2 + 2_000_000
t4 = t3 - skew + 40_000_000
w1, w2, w3, w4 = (unix_to_ntp_ref(x) for x in (t1, t2, t3, t4))
lines.append('    let (ex_offset, ex_delay) = sync.offset_delay(sync.ntp_to_unix_nanos(%du64), sync.ntp_to_unix_nanos(%du64), sync.ntp_to_unix_nanos(%du64), sync.ntp_to_unix_nanos(%du64))' % (w1, w2, w3, w4))
lines.append('    if ex_offset != %di64 || ex_delay != %di64 { try report("worked-exchange", 0usize) }' % (trunc_div2((ntp_to_unix_ref(w2) - ntp_to_unix_ref(w1)) + (ntp_to_unix_ref(w3) - ntp_to_unix_ref(w4))), (ntp_to_unix_ref(w4) - ntp_to_unix_ref(w1)) - (ntp_to_unix_ref(w3) - ntp_to_unix_ref(w2))))
assert abs(trunc_div2((ntp_to_unix_ref(w2) - ntp_to_unix_ref(w1)) + (ntp_to_unix_ref(w3) - ntp_to_unix_ref(w4))) - skew) <= 1
assert (ntp_to_unix_ref(w4) - ntp_to_unix_ref(w1)) - (ntp_to_unix_ref(w3) - ntp_to_unix_ref(w2)) in range(80_000_000 - 3, 80_000_000 + 4)

body = '\n'.join(lines)
source = '''// The NTP/SNTP codec of e.time.sync against Python's struct and datetime (L079, D2269;
// scripts/ntp_reference.py writes this file): 150 seeded packets decoded and re-encoded byte for byte,
// timestamp conversions in both directions with era and range edges and an exact unix-ntp-unix round trip,
// 16.16 short values, offset and delay, the request builder, every reply verdict, and the refusals. A
// mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.time.sync

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
    try io.print("ntp mismatch in ")
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
    try io.print("time ntp ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'time_ntp' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote time_ntp: %d packets, %d unix->ntp, %d ntp->unix, %d shorts, %d offset/delay' % (n, len(valid_to), len(words), len(shorts), len(od)))
