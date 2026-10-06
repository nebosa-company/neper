#!/usr/bin/env python3
# Assemble a NeperOS program archive (D2151, C105): a 4-byte little-endian magic 0x4E455041, a
# 4-byte program count, then for each program a 8-byte offset and 8-byte length (offsets relative
# to the archive base), then the programs themselves, each 8-byte aligned. The kernel parses this
# on `-append shell` and loads program 0 as `init`. Usage:
#   build-shell-archive.py <out.img> <prog0.img> <prog1.img> ...
import struct
import sys


def align8(n):
    return (n + 7) & ~7


def main():
    out = sys.argv[1]
    blobs = [open(p, "rb").read() for p in sys.argv[2:]]
    count = len(blobs)
    toc = 8 + count * 16
    offsets = []
    cur = align8(toc)
    for b in blobs:
        offsets.append(cur)
        cur = align8(cur + len(b))
    buf = bytearray(cur)
    struct.pack_into("<II", buf, 0, 0x4E455041, count)
    for i, b in enumerate(blobs):
        struct.pack_into("<QQ", buf, 8 + i * 16, offsets[i], len(b))
        buf[offsets[i]:offsets[i] + len(b)] = b
    with open(out, "wb") as f:
        f.write(buf)


if __name__ == "__main__":
    main()
