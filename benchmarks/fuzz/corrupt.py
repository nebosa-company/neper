# Corrupts an artifact for the suites' H24 cases (D343): `truncate` keeps the first
# half; `flip` flips a byte every four kibibytes past the header and recomputes the
# checksum, so the file passes the checksum and every reader past it sees the bytes;
# `cycle FROM TO` (D472) rewrites every occurrence of the module name FROM as TO, of the
# same length, and recomputes the checksum -- an artifact whose edges name a module
# that imports it, which no source can produce.
#
#   python benchmarks/fuzz/corrupt.py truncate|flip PATH
#   python benchmarks/fuzz/corrupt.py cycle PATH FROM TO
#   python benchmarks/fuzz/corrupt.py manifest MANIFEST ARTIFACT MODULE
import sys
import json

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
    else:
        for at in range(200, len(data), 4096):
            data[at] ^= 0x5A
    table = []
    for entry in range(256):
        crc = entry
        for _ in range(8):
            crc = (crc >> 1) ^ 0x82F63B78 if crc & 1 else crc >> 1
        table.append(crc)
    crc = 0xFFFFFFFF
    for i, b in enumerate(data):
        if 28 <= i < 32:
            b = 0
        crc = table[(crc ^ b) & 255] ^ (crc >> 8)
    data[28:32] = (crc ^ 0xFFFFFFFF).to_bytes(4, 'little')
with open(path, 'wb') as f:
    f.write(data)
