#!/usr/bin/env python3
"""Build a NeperOS filesystem disk image (neperos/src/fs.e's layout) with files already on it, for fixtures.

  make_fs_image.py OUT SIZE_MB /path=SOURCE ...

Sector 0 is the superblock (magic 'NESF' little-endian 0x4653454E, then the next free block), sector 1 the root
directory; a directory is one block of sixteen 32-byte entries (name 20, kind 1, day 3, first block 4, size 4);
a file is a run of consecutive blocks from its entry's block. Parent directories of a path are made as needed.
"""
import struct
import sys
from pathlib import Path

SECTOR = 512
ENTRIES = 16
MAGIC = 0x4653454E


class Image:
    def __init__(self, size):
        self.data = bytearray(size)
        self.next = 2
        struct.pack_into("<I", self.data, 0, MAGIC)
        self.dirs = {"/": 1}
        self.used = {1: 0}

    def alloc(self, blocks):
        first = self.next
        self.next += blocks
        if self.next * SECTOR > len(self.data):
            raise SystemExit("image too small")
        struct.pack_into("<I", self.data, 4, self.next)
        return first

    def add_entry(self, dir_block, name, kind, block, size):
        if len(name.encode()) > 20:
            raise SystemExit(f"name too long: {name}")
        base = dir_block * SECTOR
        for i in range(ENTRIES):
            at = base + i * 32
            if self.data[at + 20] == 0:
                self.data[at:at + 20] = name.encode().ljust(20, b"\0")
                self.data[at + 20] = kind
                struct.pack_into("<I", self.data, at + 24, block)
                struct.pack_into("<I", self.data, at + 28, size)
                return
        raise SystemExit("directory full")

    def ensure_dir(self, path):
        if path in self.dirs:
            return self.dirs[path]
        parent, _, leaf = path.rstrip("/").rpartition("/")
        parent_block = self.ensure_dir(parent or "/")
        block = self.alloc(1)
        self.add_entry(parent_block, leaf, 2, block, 0)
        self.dirs[path] = block
        return block

    def add_file(self, path, content):
        parent, _, leaf = path.rpartition("/")
        dir_block = self.ensure_dir(parent or "/")
        blocks = max(1, (len(content) + SECTOR - 1) // SECTOR)
        first = self.alloc(blocks)
        self.data[first * SECTOR:first * SECTOR + len(content)] = content
        self.add_entry(dir_block, leaf, 1, first, len(content))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    image = Image(int(sys.argv[2]) * 1024 * 1024)
    for spec in sys.argv[3:]:
        path, _, source = spec.partition("=")
        image.add_file(path, Path(source).read_bytes())
    Path(sys.argv[1]).write_bytes(bytes(image.data))
    print("wrote", sys.argv[1])
    return 0


sys.exit(main())
