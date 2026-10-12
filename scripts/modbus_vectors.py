"""Generate the x_modbus_wire fixture: vectors from pymodbus.

Oracle: pymodbus's request and response classes give the PDU bytes (`bytes([function_code]) + encode()`), its three
framers (`FramerSocket`, `FramerRTU`, `FramerAscii`) the TCP, RTU and ASCII frames, `FramerRTU.compute_CRC` and
`FramerAscii.compute_LRC` the checksums, and `ModbusClientMixin.convert_to_registers`/`convert_from_registers` the
typed register values in both word orders. The slave model has no library oracle that runs without a server
datastore (pymodbus's needs an event loop and its own address offset), so the expected responses and bank states come
from an independent reference slave written here straight from the Modbus Application Protocol specification
(V1.1b3 section 6: exception order, quantity limits, write-before-read).

    PYTHONPATH=DIR python scripts/modbus_vectors.py
"""
import os
import random
import struct
import sys

from pymodbus.client.mixin import ModbusClientMixin as M
from pymodbus.framer import FramerAscii, FramerRTU, FramerSocket
from pymodbus.pdu import DecodePDU, bit_message as bm, register_message as rm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x4D4F4442)
lines = []


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


def pdu_of(obj):
    return bytes([obj.function_code]) + obj.encode()


def pack_bits(bits):
    out = bytearray((len(bits) + 7) // 8)
    for i, b in enumerate(bits):
        if b:
            out[i // 8] |= 1 << (i % 8)
    return bytes(out)


# ---- requests
def render_request(fc, address=0, count=0, value=0, and_mask=0, or_mask=0, raddr=0, rcount=0, data=b''):
    return '%d:%d:%d:%d:%d:%d:%d:%d:%s' % (fc, address, count, value, and_mask, or_mask, raddr, rcount, hx(data))


REQS = []   # (spec text, pdu bytes, parsed render)
for _ in range(12):
    fc = rng.choice([1, 2, 3, 4])
    cls = {1: bm.ReadCoilsRequest, 2: bm.ReadDiscreteInputsRequest, 3: rm.ReadHoldingRegistersRequest, 4: rm.ReadInputRegistersRequest}[fc]
    a, c = rng.randrange(0, 65536), rng.randrange(1, 126)
    pdu = pdu_of(cls(address=a, count=c, dev_id=1))
    REQS.append(('rd:%d:%d:%d' % (fc, a, c), pdu, render_request(fc, a, c)))
for _ in range(5):
    a = rng.randrange(0, 65536)
    on = rng.random() < 0.5
    pdu = pdu_of(bm.WriteSingleCoilRequest(address=a, bits=[on], dev_id=1))
    REQS.append(('ws:5:%d:%d' % (a, 65280 if on else 0), pdu, render_request(5, a, value=65280 if on else 0)))
    v = rng.randrange(0, 65536)
    pdu = pdu_of(rm.WriteSingleRegisterRequest(address=a, registers=[v], dev_id=1))
    REQS.append(('ws:6:%d:%d' % (a, v), pdu, render_request(6, a, value=v)))
for _ in range(6):
    a = rng.randrange(0, 60000)
    bits = [rng.random() < 0.5 for _ in range(rng.randrange(1, 40))]
    pdu = pdu_of(bm.WriteMultipleCoilsRequest(address=a, bits=bits, dev_id=1))
    packed = pack_bits(bits)
    assert pdu == bytes([15]) + struct.pack('>HHB', a, len(bits), len(packed)) + packed
    REQS.append(('wc:%d:%d:%s' % (a, len(bits), hx(packed)), pdu, render_request(15, a, len(bits), len(packed), data=packed)))
    regs = [rng.randrange(0, 65536) for _ in range(rng.randrange(1, 20))]
    pdu = pdu_of(rm.WriteMultipleRegistersRequest(address=a, registers=regs, dev_id=1))
    data = b''.join(struct.pack('>H', r) for r in regs)
    REQS.append(('wr:%d:%s' % (a, ','.join(map(str, regs))), pdu, render_request(16, a, len(regs), len(data), data=data)))
for _ in range(4):
    a, am, om = rng.randrange(0, 65536), rng.randrange(0, 65536), rng.randrange(0, 65536)
    pdu = pdu_of(rm.MaskWriteRegisterRequest(address=a, and_mask=am, or_mask=om))
    REQS.append(('mk:%d:%d:%d' % (a, am, om), pdu, render_request(22, a, and_mask=am, or_mask=om)))
    ra, rc, wa = rng.randrange(0, 60000), rng.randrange(1, 20), rng.randrange(0, 60000)
    regs = [rng.randrange(0, 65536) for _ in range(rng.randrange(1, 10))]
    pdu = pdu_of(rm.ReadWriteMultipleRegistersRequest(read_address=ra, read_count=rc, write_address=wa, write_registers=regs))
    data = b''.join(struct.pack('>H', r) for r in regs)
    REQS.append(('rw:%d:%d:%d:%s' % (ra, rc, wa, ','.join(map(str, regs))), pdu, render_request(23, wa, len(regs), len(data), raddr=ra, rcount=rc, data=data)))
for spec, pdu, rendered in REQS:
    add('Q', spec, hx(pdu), rendered)

# ---- responses
def render_response(fc, exc=0, address=0, count=0, value=0, and_mask=0, or_mask=0, data=b''):
    return '%d:%d:%d:%d:%d:%d:%d:%s' % (fc, exc, address, count, value, and_mask, or_mask, hx(data))


for _ in range(5):
    bits = [rng.random() < 0.5 for _ in range(rng.randrange(1, 40))]
    for fc, cls in ((1, bm.ReadCoilsResponse), (2, bm.ReadDiscreteInputsResponse if hasattr(bm, 'ReadDiscreteInputsResponse') else bm.ReadCoilsResponse)):
        pdu = pdu_of(cls(bits=bits))
        pdu = bytes([fc]) + pdu[1:]
        add('P', hx(pdu), render_response(fc, data=pack_bits(bits)))
    regs = [rng.randrange(0, 65536) for _ in range(rng.randrange(1, 20))]
    data = b''.join(struct.pack('>H', r) for r in regs)
    add('P', hx(pdu_of(rm.ReadHoldingRegistersResponse(registers=regs))), render_response(3, data=data))
    add('P', hx(pdu_of(rm.ReadInputRegistersResponse(registers=regs))), render_response(4, data=data))
    add('P', hx(pdu_of(rm.ReadWriteMultipleRegistersResponse(registers=regs))), render_response(23, data=data))
    a = rng.randrange(0, 65536)
    add('P', hx(pdu_of(bm.WriteSingleCoilResponse(address=a, bits=[True]))), render_response(5, address=a, value=65280))
    add('P', hx(pdu_of(rm.WriteSingleRegisterResponse(address=a, registers=[7]))), render_response(6, address=a, value=7))
    add('P', hx(pdu_of(bm.WriteMultipleCoilsResponse(address=a, count=9))), render_response(15, address=a, count=9))
    add('P', hx(pdu_of(rm.WriteMultipleRegistersResponse(address=a, count=4))), render_response(16, address=a, count=4))
    add('P', hx(pdu_of(rm.MaskWriteRegisterResponse(address=a, and_mask=0xF2, or_mask=0x25))), render_response(22, address=a, and_mask=0xF2, or_mask=0x25))
for fc in (1, 3, 5, 16, 23):
    for code in (1, 2, 3, 4):
        e = rm.ExceptionResponse(fc, code)
        pdu = bytes([e.function_code]) + e.encode()
        assert pdu == bytes([fc | 0x80, code])
        add('P', hx(pdu), render_response(fc, exc=code))
for bad in [b'', b'\x03', b'\x03\x04\x00\x01', b'\x83', b'\x83\x02\x00', b'\x05\x00\x01\x00', b'\x06\x00\x01\x12', b'\x7f\x00\x00', b'\x03\x03\x00\x01\x00']:
    add('Pb', hx(bad))
for bad in [b'', b'\x03\x00', b'\x03\x00\x10\x00\x03\x00', b'\x10\x00\x01\x00\x02\x04\x00\x01', b'\x18\x00\x01', b'\x7f\x00\x00\x00\x00', b'\x16\x00\x01\x00\x02']:
    add('Qb', hx(bad))

# ---- framing
fs, fr, fa = FramerSocket(DecodePDU(False)), FramerRTU(DecodePDU(False)), FramerAscii(DecodePDU(False))
for _ in range(14):
    a, c = rng.randrange(0, 65536), rng.randrange(1, 126)
    unit, tid = rng.randrange(1, 248), rng.randrange(0, 65536)
    if rng.random() < 0.5:
        obj = rm.ReadHoldingRegistersRequest(address=a, count=c, dev_id=unit)
    else:
        obj = rm.WriteMultipleRegistersRequest(address=a, registers=[rng.randrange(65536) for _ in range(rng.randrange(1, 10))], dev_id=unit)
    obj.transaction_id = tid
    pdu = pdu_of(obj)
    add('T', unit, tid, hx(pdu), hx(fs.buildFrame(obj)), hx(fr.buildFrame(obj)), hx(fa.buildFrame(obj)))
for _ in range(10):
    data = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 40)))
    # pymodbus returns the CRC byte-swapped (its RTU framer packs it big-endian so the low byte goes out first).
    swapped = FramerRTU.compute_CRC(data)
    add('K', hx(data), ((swapped & 0xFF) << 8) | (swapped >> 8), FramerAscii.compute_LRC(data))
base_rtu = fr.buildFrame(rm.ReadHoldingRegistersRequest(address=1, count=2, dev_id=3))
bad_crc = bytearray(base_rtu)
bad_crc[-1] ^= 1
add('Fb', 'rtu', hx(bytes(bad_crc)), 'BadChecksum')
add('Fb', 'rtu', hx(b'\x03\x03'), 'Truncated')
base_tcp = fs.buildFrame(rm.ReadHoldingRegistersRequest(address=1, count=2, dev_id=3))
nonzero = bytearray(base_tcp)
nonzero[3] = 1
add('Fb', 'tcp', hx(bytes(nonzero)), 'Invalid')
add('Fb', 'tcp', hx(base_tcp[:8]), 'Truncated')
short_len = bytearray(base_tcp)
short_len[5] = 1
add('Fb', 'tcp', hx(bytes(short_len)), 'Invalid')
base_ascii = fa.buildFrame(rm.ReadHoldingRegistersRequest(address=1, count=2, dev_id=3))
bad_lrc = bytearray(base_ascii)
bad_lrc[-3] = ord('0') if bad_lrc[-3] != ord('0') else ord('1')
add('Fb', 'ascii', hx(bytes(bad_lrc)), 'BadChecksum')
add('Fb', 'ascii', hx(b'0103000100028'), 'Invalid')
add('Fb', 'ascii', hx(b':01030001000Z\r\n'), 'Invalid')

# ---- typed registers
TYPES = [('INT16', 1, 'h'), ('UINT16', 1, 'H'), ('INT32', 2, 'i'), ('UINT32', 2, 'I'), ('INT64', 4, 'q'), ('UINT64', 4, 'Q'), ('FLOAT32', 2, 'f'), ('FLOAT64', 4, 'd')]
for name, words, code in TYPES:
    dt = M.DATATYPE[name]
    for order in ('big', 'little'):
        for _ in range(3):
            if code in 'fd':
                v = rng.choice([0.0, 1.5, -2.25, 3.141592653589793, 1e-30, 6.5e20, -0.0, float('inf')]) if code == 'd' else rng.choice([0.0, 1.5, -2.25, 3.5, 1e-30, 6.5e20, -0.0, float('inf')])
                if code == 'f':
                    v = struct.unpack('>f', struct.pack('>f', v))[0]
            else:
                bits = struct.calcsize(code) * 8
                v = rng.randrange(-(2 ** (bits - 1)), 2 ** (bits - 1)) if code.islower() else rng.randrange(0, 2 ** bits)
            regs = M.convert_to_registers(v, dt, word_order=order)
            assert len(regs) == words
            back = M.convert_from_registers(regs, dt, word_order=order)
            assert back == v or (v != v)
            raw = struct.pack('>' + code, v)
            add('V', name, order, ','.join(map(str, regs)), hx(raw))

# ---- slave scenarios (independent reference model of the specification)
def ref_slave(banks, pdu):
    coils, discrete, holding, inputs = banks
    fc = pdu[0]
    exc = lambda code: bytes([fc | 0x80, code])
    known = fc in (1, 2, 3, 4, 5, 6, 15, 16, 22, 23)
    if not known:
        return exc(1)
    try:
        if fc in (1, 2, 3, 4):
            if len(pdu) != 5:
                return exc(3)
            a, c = struct.unpack('>HH', pdu[1:])
            if fc in (1, 2):
                bank = coils if fc == 1 else discrete
                if not 1 <= c <= 2000:
                    return exc(3)
                if a + c > len(bank):
                    return exc(2)
                return bytes([fc, (c + 7) // 8]) + pack_bits([bank[a + i] for i in range(c)])
            bank = holding if fc == 3 else inputs
            if not 1 <= c <= 125:
                return exc(3)
            if a + c > len(bank):
                return exc(2)
            return bytes([fc, 2 * c]) + b''.join(struct.pack('>H', bank[a + i]) for i in range(c))
        if fc in (5, 6):
            if len(pdu) != 5:
                return exc(3)
            a, v = struct.unpack('>HH', pdu[1:])
            if fc == 5:
                if v not in (0, 0xFF00):
                    return exc(3)
                if a >= len(coils):
                    return exc(2)
                coils[a] = 1 if v else 0
            else:
                if a >= len(holding):
                    return exc(2)
                holding[a] = v
            return pdu
        if fc == 15:
            if len(pdu) < 6:
                return exc(3)
            a, c, bc = struct.unpack('>HHB', pdu[1:6])
            data = pdu[6:]
            if len(data) != bc:
                return exc(3)
            if not 1 <= c <= 1968 or bc != (c + 7) // 8:
                return exc(3)
            if a + c > len(coils):
                return exc(2)
            for i in range(c):
                coils[a + i] = (data[i // 8] >> (i % 8)) & 1
            return struct.pack('>BHH', 15, a, c)
        if fc == 16:
            if len(pdu) < 6:
                return exc(3)
            a, c, bc = struct.unpack('>HHB', pdu[1:6])
            data = pdu[6:]
            if len(data) != bc:
                return exc(3)
            if not 1 <= c <= 123 or bc != 2 * c:
                return exc(3)
            if a + c > len(holding):
                return exc(2)
            for i in range(c):
                holding[a + i] = struct.unpack('>H', data[2 * i:2 * i + 2])[0]
            return struct.pack('>BHH', 16, a, c)
        if fc == 22:
            if len(pdu) != 7:
                return exc(3)
            a, am, om = struct.unpack('>HHH', pdu[1:])
            if a >= len(holding):
                return exc(2)
            holding[a] = (holding[a] & am) | (om & ~am & 0xFFFF)
            return pdu
        if fc == 23:
            if len(pdu) < 10:
                return exc(3)
            ra, rc, wa, wc, bc = struct.unpack('>HHHHB', pdu[1:10])
            data = pdu[10:]
            if len(data) != bc:
                return exc(3)
            if not 1 <= rc <= 125 or not 1 <= wc <= 121 or bc != 2 * wc:
                return exc(3)
            if ra + rc > len(holding) or wa + wc > len(holding):
                return exc(2)
            for i in range(wc):
                holding[wa + i] = struct.unpack('>H', data[2 * i:2 * i + 2])[0]
            return bytes([23, 2 * rc]) + b''.join(struct.pack('>H', holding[ra + i]) for i in range(rc))
    except struct.error:
        return exc(3)


def bank_text(b):
    return ''.join(str(x) for x in b) if max(b, default=0) <= 1 else ','.join(map(str, b))


for case in range(14):
    coils = [rng.randrange(2) for _ in range(40)]
    discrete = [rng.randrange(2) for _ in range(24)]
    holding = [rng.randrange(65536) for _ in range(30)]
    inputs = [rng.randrange(65536) for _ in range(20)]
    banks_init = (list(coils), list(discrete), list(holding), list(inputs))
    banks = (coils, discrete, holding, inputs)
    reqs = []
    for _ in range(rng.randrange(6, 16)):
        k = rng.randrange(14)
        if k == 0:
            reqs.append(struct.pack('>BHH', rng.choice([1, 2]), rng.randrange(0, 45), rng.choice([0, 1, 5, 16, 40, 2001])))
        elif k == 1:
            reqs.append(struct.pack('>BHH', rng.choice([3, 4]), rng.randrange(0, 35), rng.choice([0, 1, 4, 10, 30, 126])))
        elif k == 2:
            reqs.append(struct.pack('>BHH', 5, rng.randrange(0, 45), rng.choice([0, 0xFF00, 0xFF00, 1])))
        elif k == 3:
            reqs.append(struct.pack('>BHH', 6, rng.randrange(0, 35), rng.randrange(65536)))
        elif k == 4:
            c = rng.randrange(1, 20)
            bits = [rng.randrange(2) for _ in range(c)]
            packed = pack_bits(bits)
            bc = len(packed) if rng.random() < 0.9 else len(packed) + 1
            reqs.append(struct.pack('>BHHB', 15, rng.randrange(0, 45), c, bc) + packed)
        elif k == 5:
            c = rng.randrange(1, 8)
            regs = [rng.randrange(65536) for _ in range(c)]
            bc = 2 * c if rng.random() < 0.9 else 2 * c - 1
            reqs.append(struct.pack('>BHHB', 16, rng.randrange(0, 35), c, bc) + b''.join(struct.pack('>H', r) for r in regs))
        elif k == 6:
            reqs.append(struct.pack('>BHHH', 22, rng.randrange(0, 35), rng.randrange(65536), rng.randrange(65536)))
        elif k == 7:
            wc = rng.randrange(1, 5)
            regs = [rng.randrange(65536) for _ in range(wc)]
            reqs.append(struct.pack('>BHHHHB', 23, rng.randrange(0, 30), rng.randrange(0, 8), rng.randrange(0, 30), wc, 2 * wc) + b''.join(struct.pack('>H', r) for r in regs))
        elif k == 8:
            reqs.append(bytes([rng.choice([7, 8, 17, 43, 100])]) + bytes(rng.randrange(256) for _ in range(rng.randrange(0, 5))))
        elif k == 9:
            reqs.append(bytes([rng.choice([1, 3, 5, 6, 15, 16, 22, 23])]) + bytes(rng.randrange(256) for _ in range(rng.randrange(0, 3))))
        else:
            reqs.append(struct.pack('>BHH', rng.choice([3, 1]), rng.randrange(0, 20), rng.randrange(1, 6)))
    resps = [ref_slave(banks, r) for r in reqs]
    add('S', ','.join(map(str, banks_init[0])), ','.join(map(str, banks_init[1])), ','.join(map(str, banks_init[2])), ','.join(map(str, banks_init[3])),
        ';'.join(hx(r) for r in reqs), ';'.join(hx(r) for r in resps), ','.join(map(str, coils)), ','.join(map(str, holding)))

# ---- write
chunks, step = [], 30
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'modbus_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_modbus_wire', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> x_modbus_wire' % (len(lines), len(chunks)))
