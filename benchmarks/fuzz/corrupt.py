# Corrupts an artifact for the suites' H24 cases (D343): `truncate` keeps the first
# half; `flip` flips a byte every four kibibytes past the header and recomputes the
# checksum, so the file passes the checksum and every reader past it sees the bytes.
#
#   python benchmarks/fuzz/corrupt.py truncate|flip PATH
import sys

mode, path = sys.argv[1], sys.argv[2]
data = bytearray(open(path, 'rb').read())
if mode == 'truncate':
    data = data[:len(data) // 2]
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
