"""Comparing images whose debug information may differ.

    python benchmarks/metamorphic/images.py A B

exits 0 when A and B are the same bytes once each image's debug sections are zeroed, and
1 with the first differing offset otherwise. A rename reaches the debug information and
nothing else (D1605), so this is the byte-for-byte check for a renamed build (D1640).
"""
import struct
import sys


def without_debug_sections(image):
    """The image with its DWARF sections' bytes zeroed (D1605): since D1582 the debug
    information names every local, so a rename reaches those bytes and no others. ELF
    names them `.debug_*` in its section-name table; PE, MinGW-style, as `/N` whose
    name is at offset N of the COFF string table."""
    out = bytearray(image)
    if image[:4] == b'\x7fELF':
        shoff = struct.unpack_from('<Q', image, 0x28)[0]
        shentsize, shnum, shstrndx = struct.unpack_from('<HHH', image, 0x3a)
        names = shoff + shstrndx * shentsize
        names_offset = struct.unpack_from('<Q', image, names + 0x18)[0]
        for i in range(shnum):
            header = shoff + i * shentsize
            name_at = struct.unpack_from('<I', image, header)[0]
            name = image[names_offset + name_at:image.index(b'\0', names_offset + name_at)]
            offset, size = struct.unpack_from('<QQ', image, header + 0x18)
            if name.startswith(b'.debug_') and struct.unpack_from('<I', image, header + 4)[0] != 8:
                out[offset:offset + size] = bytes(size)
        return bytes(out)
    if image[:2] == b'MZ':
        pe = struct.unpack_from('<I', image, 0x3c)[0]
        sections, = struct.unpack_from('<H', image, pe + 6)
        symbols, symbol_count = struct.unpack_from('<II', image, pe + 12)
        optional, = struct.unpack_from('<H', image, pe + 20)
        strings = symbols + symbol_count * 18
        for i in range(sections):
            header = pe + 24 + optional + i * 40
            name = image[header:header + 8].rstrip(b'\0')
            if name.startswith(b'/') and symbols:
                at = strings + int(name[1:])
                name = image[at:image.index(b'\0', at)]
            size, offset = struct.unpack_from('<II', image, header + 16)
            if name.startswith(b'.debug_'):
                out[offset:offset + size] = bytes(size)
        return bytes(out)
    return image


if __name__ == '__main__':
    a = without_debug_sections(open(sys.argv[1], 'rb').read())
    b = without_debug_sections(open(sys.argv[2], 'rb').read())
    if a != b:
        at = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        sys.exit('%s and %s differ outside their debug sections at byte %d' % (sys.argv[1], sys.argv[2], at))
