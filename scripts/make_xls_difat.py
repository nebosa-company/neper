"""Writes tests/data/xls/difat.xls: datasets.xls's Workbook stream padded with zeros past 7 MB, so the
compound file needs 110 FAT sectors and one DIFAT sector. The padding follows the last EOF record, which
no reader looks at."""
import struct, sys

SECT = 512
END, FATSECT, DIFSECT, FREE = 0xFFFFFFFE, 0xFFFFFFFD, 0xFFFFFFFC, 0xFFFFFFFF


def workbook_stream(data):
    ssz = 1 << struct.unpack_from("<H", data, 30)[0]
    nfat = struct.unpack_from("<I", data, 44)[0]
    dirstart = struct.unpack_from("<I", data, 48)[0]
    fat = []
    for i in range(nfat):
        s = struct.unpack_from("<I", data, 76 + 4 * i)[0]
        fat += struct.unpack_from("<%dI" % (ssz // 4), data, (s + 1) * ssz)
    def chain(s):
        out = b""
        while s < 0xFFFFFFFA:
            out += data[(s + 1) * ssz:(s + 2) * ssz]
            s = fat[s]
        return out
    d = chain(dirstart)
    for i in range(0, len(d), 128):
        name = d[i:i + 64].decode("utf-16-le").split("\0")[0]
        if name in ("Workbook", "Book"):
            start, size = struct.unpack_from("<II", d, i + 116)
            return chain(start)[:size]
    raise SystemExit("no Workbook stream")


def main(src, dst, pad_to=7_300_000):
    wb = workbook_stream(open(src, "rb").read())
    wb += b"\0" * (pad_to - len(wb))
    n = -(-len(wb) // SECT)
    nfat = 1
    while True:
        total = n + nfat + 1 + 1  # stream, fat, difat, directory
        if nfat * 128 >= total:
            break
        nfat += 1
    assert nfat > 109, nfat
    fat_at, difat_at, dir_at = n, n + nfat, n + nfat + 1
    fat = [FREE] * (nfat * 128)
    for i in range(n - 1):
        fat[i] = i + 1
    fat[n - 1] = END
    for i in range(nfat):
        fat[fat_at + i] = FATSECT
    fat[difat_at] = DIFSECT
    fat[dir_at] = END

    def entry(name, kind, start, size, left=0xFFFFFFFF, right=0xFFFFFFFF, child=0xFFFFFFFF):
        nm = name.encode("utf-16-le") + b"\0\0"
        e = nm.ljust(64, b"\0") + struct.pack("<HBB", len(nm), kind, 1)
        e += struct.pack("<III", left, right, child) + b"\0" * 16 + b"\0" * 4 + b"\0" * 16
        e += struct.pack("<II", start, size) + struct.pack("<I", 0)
        return e

    root = entry("Root Entry", 5, END, 0, child=1)
    book = entry("Workbook", 2, 0, len(wb))
    dirsec = (root + book).ljust(SECT, b"\0")
    hdr_difat = [fat_at + i for i in range(109)]
    hdr = bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) + b"\0" * 16
    hdr += struct.pack("<HHHHH", 0x3E, 3, 0xFFFE, 9, 6) + b"\0" * 6
    hdr += struct.pack("<IIIIIIII", 0, nfat, dir_at, 0, 4096, END, 0, difat_at)
    hdr += struct.pack("<I", 1)  # one DIFAT sector
    hdr += struct.pack("<109I", *hdr_difat)
    assert len(hdr) == SECT
    difat = [fat_at + 109 + i for i in range(nfat - 109)]
    difat += [FREE] * (127 - len(difat)) + [END]
    out = bytearray(hdr)
    out += wb.ljust(n * SECT, b"\0")
    out += struct.pack("<%dI" % len(fat), *fat)
    out += struct.pack("<128I", *difat)
    out += dirsec
    open(dst, "wb").write(out)
    print(dst, len(out), "bytes,", nfat, "FAT sectors")


main(sys.argv[1], sys.argv[2])
