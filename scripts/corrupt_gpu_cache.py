#!/usr/bin/env python3
"""Corrupt a Vulkan cache header while keeping Neper's outer CRC valid."""

import pathlib
import sys


def crc32c(data: bytes) -> int:
    value = 0xFFFFFFFF
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (0x82F63B78 if value & 1 else 0)
    return value ^ 0xFFFFFFFF


path = pathlib.Path(sys.argv[1])
record = bytearray(path.read_bytes())
if record[:8] != b"NEPGPU01" or len(record) < 60:
    raise SystemExit("not a Neper Vulkan pipeline cache")
record[28] ^= 0xFF
record[24:28] = crc32c(record[28:]).to_bytes(4, "little")
path.write_bytes(record)
