# Corrupts an artifact for the suites' H24 cases (D343): `truncate` keeps the first
# half; `flip` flips a byte every four kibibytes past the header and recomputes the
# checksum, so the file passes the checksum and every reader past it sees the bytes;
# `cycle FROM TO` (D472) rewrites every occurrence of the module name FROM as TO, of the
# same length, and recomputes the checksum -- an artifact whose edges name a module
# that imports it, which no source can produce.
#
#   python benchmarks/fuzz/corrupt.py truncate|flip PATH
#   python benchmarks/fuzz/corrupt.py cycle PATH FROM TO
#   python benchmarks/fuzz/corrupt.py crc-preserve PATH
#   python benchmarks/fuzz/corrupt.py manifest MANIFEST ARTIFACT MODULE
import sys
import json
import struct

mode, path = sys.argv[1], sys.argv[2]
if mode == 'manifest':
    artifact, module = sys.argv[3], sys.argv[4]
    document = json.load(open(path, encoding='utf-8'))
    checksum = int.from_bytes(open(artifact, 'rb').read()[28:32], 'little')
    entry = next(item for item in document['incremental'] if item['module'] == module)
    entry['artifact_crc32c'] = f'{checksum:08x}'
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(document, f, separators=(',', ':'))
        f.write('\n')
    raise SystemExit(0)
data = bytearray(open(path, 'rb').read())
if mode == 'truncate':
    data = data[:len(data) // 2]
else:
    if mode == 'cycle':
        old, new = sys.argv[3].encode(), sys.argv[4].encode()
        assert len(old) == len(new), 'the names must have one length'
        data = bytearray(bytes(data).replace(old, new))
    elif mode == 'flip':
        for at in range(200, len(data), 4096):
            data[at] ^= 0x5A
    elif mode != 'crc-preserve':
        raise SystemExit('unknown corruption mode: ' + mode)
    table = []
    for entry in range(256):
        crc = entry
        for _ in range(8):
            crc = (crc >> 1) ^ 0x82F63B78 if crc & 1 else crc >> 1
        table.append(crc)
    def crc32c(content):
        crc = 0xFFFFFFFF
        for i, b in enumerate(content):
            if 28 <= i < 32:
                b = 0
            crc = table[(crc ^ b) & 255] ^ (crc >> 8)
        return crc ^ 0xFFFFFFFF

    if mode == 'crc-preserve':
        original = bytes(data)
        target = int.from_bytes(data[28:32], 'little')
        count, directory = struct.unpack_from('<II', data, 20)
        sections = [struct.unpack_from('<IIQQ', data, directory + i * 24) for i in range(count)]
        code = next(row for row in sections if row[0] == 5)
        code_start = code[2] + 4 + 24
        code_length = struct.unpack_from('<I', data, code[2] + 4 + 16)[0]
        assert code_length != 0, 'artifact has no machine code'
        data[code_start] ^= 1
        ordered = sorted(sections, key=lambda row: row[2])
        gaps = [left[2] + left[3] for left, right in zip(ordered, ordered[1:])
                if right[2] - (left[2] + left[3]) >= 4]
        assert gaps, 'artifact has no checksum-neutral padding'
        patch = gaps[0]
        baseline = crc32c(data)
        basis = {}
        for bit in range(32):
            candidate = bytearray(data)
            candidate[patch + bit // 8] ^= 1 << (bit % 8)
            delta, mask = crc32c(candidate) ^ baseline, 1 << bit
            while delta:
                pivot = delta.bit_length() - 1
                if pivot not in basis:
                    basis[pivot] = delta, mask
                    break
                row, row_mask = basis[pivot]
                delta ^= row
                mask ^= row_mask
        delta, mask = baseline ^ target, 0
        while delta:
            row, row_mask = basis[delta.bit_length() - 1]
            delta ^= row
            mask ^= row_mask
        for bit in range(32):
            if mask & (1 << bit):
                data[patch + bit // 8] ^= 1 << (bit % 8)
        assert data != original and crc32c(data) == target
    else:
        data[28:32] = crc32c(data).to_bytes(4, 'little')
with open(path, 'wb') as f:
    f.write(data)
