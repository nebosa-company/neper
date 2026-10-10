# -*- coding: utf-8 -*-
"""Vectors for `e.net.packet` and `e.net.pcap` (L051).

An independent implementation written straight from the specs (RFC 791, 793, 768, 792, 826, 1071, 8200, 4443; the pcap
and pcapng file formats) builds frames and capture files with `struct`, and a second, separate parser here gives the
expected decode; the fixture runs Neper's codecs over the same bytes. Writes tests/selfhost/fixtures/link/net_packet.
Usage: python scripts/packet_vectors.py
"""
import json
import os
import random
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x51ab)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


def rbytes(n):
    return bytes(rng.randrange(256) for _ in range(n))


def csum(data, seed=0):
    s = seed
    for i in range(0, len(data) - 1, 2):
        s += (data[i] << 8) | data[i + 1]
    if len(data) % 2:
        s += data[-1] << 8
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def pseudo4(src, dst, proto, n):
    return sum((src[i] << 8) | src[i + 1] for i in (0, 2)) + sum((dst[i] << 8) | dst[i + 1] for i in (0, 2)) + proto + n


def pseudo6(src, dst, proto, n):
    s = sum((src[i] << 8) | src[i + 1] for i in range(0, 16, 2)) + sum((dst[i] << 8) | dst[i + 1] for i in range(0, 16, 2))
    return s + (n >> 16) + (n & 0xFFFF) + proto


def eth(dst, src, ethertype, payload, tags=()):
    out = dst + src
    for outer, tci in tags:
        out += struct.pack('>HH', 0x88A8 if outer else 0x8100, tci)
    return out + struct.pack('>H', ethertype) + payload


def ipv4(src, dst, proto, payload, ttl=64, tos=0, ident=0, flags=0, frag=0, options=b'', pad=b''):
    ihl = 5 + len(options) // 4
    total = ihl * 4 + len(payload)
    h = struct.pack('>BBHHHBBH4s4s', 0x40 | ihl, tos, total, ident, (flags << 13) | frag, ttl, proto, 0, src, dst) + options
    c = csum(h)
    h = h[:10] + struct.pack('>H', c) + h[12:]
    return h + payload + pad


def ipv6(src, dst, nh, payload, tc=0, flow=0, hop=64):
    return struct.pack('>IHBB16s16s', (6 << 28) | (tc << 20) | flow, len(payload), nh, hop, src, dst) + payload


def tcp(src, dst, sport, dport, seq, ack, flags, window, urgent, options, payload, v6=False):
    off = 5 + len(options) // 4
    seg = struct.pack('>HHIIHHHH', sport, dport, seq, ack, (off << 12) | flags, window, 0, urgent) + options + payload
    p = pseudo6(src, dst, 6, len(seg)) if v6 else pseudo4(src, dst, 6, len(seg))
    c = csum(seg, p)
    return seg[:16] + struct.pack('>H', c) + seg[18:]


def udp(src, dst, sport, dport, payload, v6=False):
    seg = struct.pack('>HHHH', sport, dport, 8 + len(payload), 0) + payload
    p = pseudo6(src, dst, 17, len(seg)) if v6 else pseudo4(src, dst, 17, len(seg))
    c = csum(seg, p) or 0xFFFF
    return seg[:6] + struct.pack('>H', c) + seg[8:]


def icmp(kind, code, rest, payload):
    m = struct.pack('>BBHI', kind, code, 0, rest) + payload
    return m[:2] + struct.pack('>H', csum(m)) + m[4:]


def icmp6(src, dst, kind, code, rest, payload):
    m = struct.pack('>BBHI', kind, code, 0, rest) + payload
    c = csum(m, pseudo6(src, dst, 58, len(m)))
    return m[:2] + struct.pack('>H', c) + m[4:]


def arp(op, smac, sip, tmac, tip):
    return struct.pack('>HHBBH6s4s6s4s', 1, 0x0800, 6, 4, op, smac, sip, tmac, tip)


class Err(Exception):
    pass


def py_parse(frame):
    """The expected decode, from the specs: a dict or an error name."""
    def need(cond, kind='truncated'):
        if not cond:
            raise Err(kind)
    out = {}
    need(len(frame) >= 14)
    at = 12
    et = struct.unpack_from('>H', frame, at)[0]
    tags = 0
    vid = pcp = 0
    while et in (0x8100, 0x88A8) and tags < 2:
        need(len(frame) >= at + 6)
        tci = struct.unpack_from('>H', frame, at + 2)[0]
        vid, pcp = tci & 0xFFF, tci >> 13
        tags += 1
        at += 4
        et = struct.unpack_from('>H', frame, at)[0]
    out['eth'] = {'dst': frame[0:6].hex(), 'src': frame[6:12].hex(), 'type': et, 'vlans': tags, 'vid': vid, 'pcp': pcp}
    p = frame[at + 2:]
    if et == 0x0806:
        need(len(p) >= 28)
        need(struct.unpack_from('>HHBB', p, 0) == (1, 0x0800, 6, 4), 'invalid')
        op, = struct.unpack_from('>H', p, 6)
        out['arp'] = {'op': op, 'smac': p[8:14].hex(), 'sip': p[14:18].hex(), 'tmac': p[18:24].hex(), 'tip': p[24:28].hex()}
        return out
    proto = None
    l4 = None
    if et == 0x0800:
        need(len(p) >= 20)
        need(p[0] >> 4 == 4, 'invalid')
        ihl = p[0] & 15
        need(ihl >= 5, 'invalid')
        need(len(p) >= ihl * 4)
        total, ident, ff, ttl, proto_, ck = struct.unpack_from('>HHHBBH', p, 2)
        need(total >= ihl * 4, 'invalid')
        need(len(p) >= total)
        header = p[:ihl * 4]
        out['ip'] = {'v': 4, 'ihl': ihl, 'dscp': p[1] >> 2, 'ecn': p[1] & 3, 'total': total, 'id': ident, 'flags': ff >> 13, 'frag': ff & 0x1FFF,
                     'ttl': ttl, 'proto': proto_, 'ck': ck, 'ckok': csum(header) == 0, 'src': p[12:16].hex(), 'dst': p[16:20].hex(), 'options': p[20:ihl * 4].hex()}
        l4 = p[ihl * 4:total]
        proto = proto_
        src, dst = p[12:16], p[16:20]
    elif et == 0x86DD:
        need(len(p) >= 40)
        need(p[0] >> 4 == 6, 'invalid')
        plen, nh, hop = struct.unpack_from('>HBB', p, 4)
        need(len(p) >= 40 + plen)
        vtf, = struct.unpack_from('>I', p, 0)
        end = 40 + plen
        at6 = 40
        frag = False
        fo = 0
        mf = False
        hops = 0
        while nh in (0, 43, 44, 60, 51):
            hops += 1
            need(hops <= 16, 'invalid')
            need(at6 + 8 <= end)
            if nh == 44:
                frag = True
                f, = struct.unpack_from('>H', p, at6 + 2)
                fo, mf = f >> 3, bool(f & 1)
                nh = p[at6]
                at6 += 8
                continue
            length = (p[at6 + 1] + 1) * 8 if nh != 51 else (p[at6 + 1] + 2) * 4
            need(at6 + length <= end)
            nh = p[at6]
            at6 += length
        out['ip'] = {'v': 6, 'tc': (vtf >> 20) & 0xFF, 'flow': vtf & 0xFFFFF, 'plen': plen, 'nh': p[6], 'hop': hop, 'src': p[8:24].hex(), 'dst': p[24:40].hex(),
                     'proto': nh, 'frag': frag, 'fo': fo, 'mf': mf}
        l4 = p[at6:end]
        proto = nh
        src, dst = p[8:24], p[24:40]
    else:
        return out
    if proto == 6:
        need(len(l4) >= 20)
        off = l4[12] >> 4
        need(off >= 5, 'invalid')
        need(len(l4) >= off * 4)
        sp, dp, seq, ack, fl, win, ck, urg = struct.unpack_from('>HHIIHHHH', l4, 0)
        ok_ck = None
        if et == 0x0800 or et == 0x86DD:
            ok_ck = ((~csum(l4, pseudo4(src, dst, 6, len(l4)) if et == 0x0800 else pseudo6(src, dst, 6, len(l4)))) & 0xFFFF) == 0xFFFF
        out['tcp'] = {'sp': sp, 'dp': dp, 'seq': seq, 'ack': ack, 'off': off, 'flags': fl & 0x1FF, 'win': win, 'ck': ck, 'urg': urg, 'ckok': ok_ck,
                      'options': l4[20:off * 4].hex(), 'payload': l4[off * 4:].hex()}
    elif proto == 17:
        need(len(l4) >= 8)
        sp, dp, ln, ck = struct.unpack_from('>HHHH', l4, 0)
        need(ln >= 8, 'invalid')
        need(len(l4) >= ln)
        out['udp'] = {'sp': sp, 'dp': dp, 'len': ln, 'ck': ck, 'payload': l4[8:ln].hex()}
    elif proto in (1, 58):
        need(len(l4) >= 8)
        k, c, ck, rest = struct.unpack_from('>BBHI', l4, 0)
        out['icmp'] = {'type': k, 'code': c, 'ck': ck, 'rest': rest, 'payload': l4[8:].hex()}
    return out


MAC = lambda: rbytes(6)
IP4 = lambda: rbytes(4)
IP6 = lambda: rbytes(16)

cases = []


def add(c):
    cases.append(c)


def frame_case(frame, label=''):
    try:
        e = {'ok': True, 'v': py_parse(frame)}
    except Err as x:
        e = {'ok': False, 'error': str(x)}
    add({'op': 'frame', 'h': frame.hex(), 'e': e})


def good_frame():
    kind = int(rng.random() * 9)
    s4, d4, s6, d6 = IP4(), IP4(), IP6(), IP6()
    tags = []
    if chance(0.25):
        tags.append((False, (rng.randrange(8) << 13) | rng.randrange(4096)))
    if chance(0.05):
        tags.insert(0, (True, rng.randrange(65536)))
    payload = rbytes(rng.randrange(0, 40))
    if kind == 0:
        return eth(MAC(), MAC(), 0x0806, arp(pick([1, 2]), MAC(), s4, MAC(), d4), tags)
    if kind == 1:
        opts = b'\x01\x01\x01\x00' if chance(0.3) else b''
        return eth(MAC(), MAC(), 0x0800, ipv4(s4, d4, 6, tcp(s4, d4, rng.randrange(65536), rng.randrange(65536), rng.randrange(1 << 32), rng.randrange(1 << 32), rng.randrange(512), rng.randrange(65536), rng.randrange(65536), pick([b'', b'\x02\x04\x05\xb4']), payload),
                                              ttl=rng.randrange(256), tos=rng.randrange(256), ident=rng.randrange(65536), flags=rng.randrange(8), frag=0, options=opts), tags)
    if kind == 2:
        return eth(MAC(), MAC(), 0x0800, ipv4(s4, d4, 17, udp(s4, d4, rng.randrange(65536), rng.randrange(65536), payload), pad=pick([b'', b'\x00\x00'])), tags)
    if kind == 3:
        return eth(MAC(), MAC(), 0x0800, ipv4(s4, d4, 1, icmp(pick([0, 8, 3]), rng.randrange(4), rng.randrange(1 << 32), payload)), tags)
    if kind == 4:
        return eth(MAC(), MAC(), 0x86DD, ipv6(s6, d6, 6, tcp(s6, d6, rng.randrange(65536), rng.randrange(65536), rng.randrange(1 << 32), rng.randrange(1 << 32), rng.randrange(512), 1000, 0, b'', payload, v6=True), tc=rng.randrange(256), flow=rng.randrange(1 << 20)), tags)
    if kind == 5:
        return eth(MAC(), MAC(), 0x86DD, ipv6(s6, d6, 17, udp(s6, d6, 53, rng.randrange(65536), payload, v6=True)), tags)
    if kind == 6:
        return eth(MAC(), MAC(), 0x86DD, ipv6(s6, d6, 58, icmp6(s6, d6, pick([128, 129, 135]), 0, rng.randrange(1 << 32), payload)), tags)
    if kind == 7:
        inner = udp(s6, d6, 1000, 2000, payload, v6=True)
        ext = struct.pack('>BBBBBBBB', 17, 0, 1, 4, 0, 0, 0, 0)  # hop-by-hop with PadN
        return eth(MAC(), MAC(), 0x86DD, ipv6(s6, d6, 0, ext + inner), tags)
    frag = struct.pack('>BBHI', 17, 0, (rng.randrange(8000) << 3) | pick([0, 1]), rng.randrange(1 << 32))
    return eth(MAC(), MAC(), 0x86DD, ipv6(s6, d6, 44, frag + rbytes(rng.randrange(0, 24))), tags)


for _ in range(160):
    f = good_frame()
    frame_case(f)
    if chance(0.5):
        frame_case(f[:rng.randrange(0, len(f))])
# deliberately broken
base = eth(MAC(), MAC(), 0x0800, ipv4(IP4(), IP4(), 17, udp(IP4(), IP4(), 1, 2, b'abc')))
for mut in range(10):
    b = bytearray(base)
    if mut == 0:
        b[14] = 0x65
    if mut == 1:
        b[14] = 0x44
    if mut == 2:
        b[16:18] = struct.pack('>H', 10)
    if mut == 3:
        b[16:18] = struct.pack('>H', 9999)
    if mut == 4:
        b[24] ^= 0xFF  # corrupt header checksum
    if mut == 5:
        b[38:40] = struct.pack('>H', 4)  # udp length < 8
    if mut == 6:
        b[38:40] = struct.pack('>H', 200)
    frame_case(bytes(b))
frame_case(eth(MAC(), MAC(), 0x0806, struct.pack('>HHBBH', 2, 0x0800, 6, 4, 1) + rbytes(20)))
frame_case(eth(MAC(), MAC(), 0x86DD, b'\x40' + rbytes(60)))
frame_case(eth(MAC(), MAC(), 0x1234, rbytes(10)))
frame_case(b'')

for _ in range(20):
    data = rbytes(rng.randrange(0, 40))
    add({'op': 'checksum', 'h': data.hex(), 'e': csum(data)})
add({'op': 'checksum', 'h': '0001f203f4f5f6f7', 'e': csum(bytes.fromhex('0001f203f4f5f6f7'))})
add({'op': 'checksum', 'h': '', 'e': 0xFFFF})

# builders
for _ in range(30):
    s4, d4, s6, d6 = IP4(), IP4(), IP6(), IP6()
    payload = rbytes(rng.randrange(0, 30))
    kind = rng.randrange(6)
    if kind == 0:
        e = ipv4(s4, d4, 17, b'\x00' * rng.randrange(0, 20), ttl=rng.randrange(256), tos=rng.randrange(256), ident=rng.randrange(65536), flags=rng.randrange(8), frag=rng.randrange(8192))
        add({'op': 'buildIpv4', 'src': s4.hex(), 'dst': d4.hex(), 'proto': 17, 'payload': len(e) - 20, 'ttl': e[8], 'tos': e[1], 'id': (e[4] << 8) | e[5],
             'flags': e[6] >> 5, 'frag': ((e[6] & 31) << 8) | e[7], 'e': e[:20].hex()})
    elif kind == 1:
        sp, dp = rng.randrange(65536), rng.randrange(65536)
        add({'op': 'buildUdp4', 'src': s4.hex(), 'dst': d4.hex(), 'sp': sp, 'dp': dp, 'payload': payload.hex(), 'e': udp(s4, d4, sp, dp, payload).hex()})
    elif kind == 2:
        sp, dp, seq, ack, fl, win, urg = rng.randrange(65536), rng.randrange(65536), rng.randrange(1 << 32), rng.randrange(1 << 32), rng.randrange(512), rng.randrange(65536), rng.randrange(65536)
        opts = pick([b'', b'\x02\x04\x05\xb4', b'\x01\x01\x04\x02'])
        add({'op': 'buildTcp4', 'src': s4.hex(), 'dst': d4.hex(), 'sp': sp, 'dp': dp, 'seq': seq, 'ack': ack, 'flags': fl, 'win': win, 'urg': urg, 'options': opts.hex(), 'payload': payload.hex(),
             'e': tcp(s4, d4, sp, dp, seq, ack, fl, win, urg, opts, payload).hex()})
    elif kind == 3:
        k, c, rest = pick([0, 8, 3]), rng.randrange(4), rng.randrange(1 << 32)
        add({'op': 'buildIcmp', 'kind': k, 'code': c, 'rest': rest, 'payload': payload.hex(), 'e': icmp(k, c, rest, payload).hex()})
    elif kind == 4:
        k, c, rest = pick([128, 129, 135]), 0, rng.randrange(1 << 32)
        add({'op': 'buildIcmp6', 'src': s6.hex(), 'dst': d6.hex(), 'kind': k, 'code': c, 'rest': rest, 'payload': payload.hex(), 'e': icmp6(s6, d6, k, c, rest, payload).hex()})
    else:
        tc, flow, nh, hop = rng.randrange(256), rng.randrange(1 << 20), pick([6, 17, 58]), rng.randrange(256)
        e = ipv6(s6, d6, nh, b'\x00' * 12, tc=tc, flow=flow, hop=hop)
        add({'op': 'buildIpv6', 'src': s6.hex(), 'dst': d6.hex(), 'tc': tc, 'flow': flow, 'nh': nh, 'hop': hop, 'payload': 12, 'e': e[:40].hex()})

# capture files
def rec_list(n):
    out = []
    t = rng.randrange(1_600_000_000, 1_700_000_000)
    for _ in range(n):
        data = rbytes(rng.randrange(0, 60))
        out.append((t, rng.randrange(1_000_000), data, len(data) + pick([0, 0, 10])))
        t += rng.randrange(0, 5)
    return out


def classic(recs, big, nano, linktype=1, snaplen=65535):
    e = '>' if big else '<'
    magic = 0xA1B23C4D if nano else 0xA1B2C3D4
    out = struct.pack(e + 'IHHiIII', magic, 2, 4, 0, 0, snaplen, linktype)
    for sec, frac, data, orig in recs:
        f = frac * 1000 if nano else frac
        out += struct.pack(e + 'IIII', sec, f, len(data), orig) + data
    return out


def pad4(b):
    return b + b'\x00' * ((-len(b)) % 4)


def block(kind, body, big):
    e = '>' if big else '<'
    total = 12 + len(pad4(body))
    return struct.pack(e + 'II', kind, total) + pad4(body) + struct.pack(e + 'I', total)


def pcapng(recs, big, tsresol, simple=False):
    e = '>' if big else '<'
    out = block(0x0A0D0D0A, struct.pack(e + 'IHHq', 0x1A2B3C4D, 1, 0, -1), big)
    opts = b''
    if tsresol is not None:
        opts = struct.pack(e + 'HH', 9, 1) + bytes([tsresol]) + b'\x00\x00\x00' + struct.pack(e + 'HH', 0, 0)
    out += block(1, struct.pack(e + 'HHI', 1, 0, 65535) + opts, big)
    res = tsresol if tsresol is not None else 6
    unit = 10 ** res
    for sec, frac, data, orig in recs:
        if simple:
            out += block(3, struct.pack(e + 'I', orig) + data, big)
        else:
            ticks = sec * unit + (frac * unit // 1_000_000)
            out += block(6, struct.pack(e + 'IIIII', 0, ticks >> 32, ticks & 0xFFFFFFFF, len(data), orig) + data, big)
        if chance(0.2):
            out += block(5, b'\x00' * 8, big)  # an interface statistics block to skip
    return out


def expect_records(recs, nano=False, res=6, simple=False):
    unit = 10 ** res
    out = []
    for sec, frac, data, orig in recs:
        if simple:
            out.append({'sec': 0, 'ns': 0, 'cap': len(data), 'orig': orig, 'h': data.hex()})
            continue
        ticks = sec * unit + (frac * unit // 1_000_000)
        s, rem = divmod(ticks, unit)
        ns = rem * (1_000_000_000 // unit) if res <= 9 else rem // (unit // 1_000_000_000)
        out.append({'sec': s, 'ns': ns, 'cap': len(data), 'orig': orig, 'h': data.hex()})
    return out


for _ in range(10):
    recs = rec_list(rng.randrange(0, 6))
    big, nano = chance(0.5), chance(0.4)
    f = classic(recs, big, nano)
    exp = [{'sec': s, 'ns': (fr * 1000 if not nano else fr * 1000), 'cap': len(d), 'orig': o, 'h': d.hex()} for s, fr, d, o in recs]
    add({'op': 'pcap', 'h': f.hex(), 'e': {'ok': True, 'link': 1, 'v': exp}})
    if len(f) > 24 and chance(0.6):
        cut = f[:rng.randrange(25, len(f))]
        # how many whole records survive, and whether the tail is damaged
        pos, got = 24, []
        err = None
        i = 0
        while True:
            if pos == len(cut):
                break
            if len(cut) - pos < 16:
                err = 'truncated'
                break
            caplen = struct.unpack_from('>I' if big else '<I', cut, pos + 8)[0]
            if pos + 16 + caplen > len(cut):
                err = 'truncated'
                break
            got.append(exp[i])
            pos += 16 + caplen
            i += 1
        add({'op': 'pcap', 'h': cut.hex(), 'e': {'ok': err is None, 'link': 1, 'v': got, 'error': err}})
for _ in range(10):
    recs = rec_list(rng.randrange(1, 5))
    big = chance(0.5)
    res = pick([None, 6, 9, 3])
    simple = chance(0.2)
    f = pcapng(recs, big, res, simple)
    add({'op': 'pcap', 'h': f.hex(), 'e': {'ok': True, 'link': 1, 'v': expect_records(recs, res=(res if res is not None else 6), simple=simple), 'ng': True}})
add({'op': 'pcap', 'h': 'deadbeef' * 8, 'e': {'ok': False, 'v': [], 'error': 'invalid'}})
add({'op': 'pcap', 'h': 'a1b2', 'e': {'ok': False, 'v': [], 'error': 'truncated'}})

# writer round trip
for _ in range(6):
    recs = rec_list(rng.randrange(0, 5))
    add({'op': 'writePcap', 'linktype': 1, 'snaplen': 65535, 'records': [{'sec': s, 'usec': fr, 'h': d.hex(), 'orig': o} for s, fr, d, o in recs], 'e': classic(recs, False, False).hex()})

BS = chr(92)
lines = [json.dumps(c, sort_keys=True) for c in cases]
chunks = []
for i in range(0, len(lines), 12):
    body = '\\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"') for l in lines[i:i + 12]) + '\\n'
    chunks.append('"' + body + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'packet_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_packet', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d cases in %d chunks -> net_packet' % (len(cases), len(chunks)))
