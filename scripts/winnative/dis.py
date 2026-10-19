"""Lists a glyph program's top-level instructions that are not pushes, with the numbers pushed just before each.

python dis.py <font file> <code> [first [last]]
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import ttProgram

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
from firstdiff import nonpush

NAMES = {}
for name, base, n in (("SVTCA", 0, 2), ("SPVTCA", 2, 2), ("SFVTCA", 4, 2), ("SPVTL", 6, 2), ("SFVTL", 8, 2), ("SPVFS", 0xA, 1), ("SFVFS", 0xB, 1), ("GPV", 0xC, 1), ("GFV", 0xD, 1),
                      ("SFVTPV", 0xE, 1), ("ISECT", 0xF, 1), ("SRP0", 0x10, 1), ("SRP1", 0x11, 1), ("SRP2", 0x12, 1), ("SZP0", 0x13, 1), ("SZP1", 0x14, 1), ("SZP2", 0x15, 1),
                      ("SZPS", 0x16, 1), ("SLOOP", 0x17, 1), ("RTG", 0x18, 1), ("RTHG", 0x19, 1), ("SMD", 0x1A, 1), ("ELSE", 0x1B, 1), ("JMPR", 0x1C, 1), ("SCVTCI", 0x1D, 1),
                      ("SSWCI", 0x1E, 1), ("SSW", 0x1F, 1), ("DUP", 0x20, 1), ("POP", 0x21, 1), ("CLEAR", 0x22, 1), ("SWAP", 0x23, 1), ("DEPTH", 0x24, 1), ("CINDEX", 0x25, 1),
                      ("MINDEX", 0x26, 1), ("ALIGNPTS", 0x27, 1), ("UTP", 0x29, 1), ("LOOPCALL", 0x2A, 1), ("CALL", 0x2B, 1), ("FDEF", 0x2C, 1), ("ENDF", 0x2D, 1), ("MDAP", 0x2E, 2),
                      ("IUP", 0x30, 2), ("SHP", 0x32, 2), ("SHC", 0x34, 2), ("SHZ", 0x36, 2), ("SHPIX", 0x38, 1), ("IP", 0x39, 1), ("MSIRP", 0x3A, 2), ("ALIGNRP", 0x3C, 1),
                      ("RTDG", 0x3D, 1), ("MIAP", 0x3E, 2), ("WS", 0x42, 1), ("RS", 0x43, 1), ("WCVTP", 0x44, 1), ("RCVT", 0x45, 1), ("GC", 0x46, 2), ("SCFS", 0x48, 1),
                      ("MD", 0x49, 2), ("MPPEM", 0x4B, 1), ("MPS", 0x4C, 1), ("FLIPON", 0x4D, 1), ("FLIPOFF", 0x4E, 1), ("LT", 0x50, 1), ("LTEQ", 0x51, 1), ("GT", 0x52, 1),
                      ("GTEQ", 0x53, 1), ("EQ", 0x54, 1), ("NEQ", 0x55, 1), ("ODD", 0x56, 1), ("EVEN", 0x57, 1), ("IF", 0x58, 1), ("EIF", 0x59, 1), ("AND", 0x5A, 1), ("OR", 0x5B, 1),
                      ("NOT", 0x5C, 1), ("DELTAP1", 0x5D, 1), ("SDB", 0x5E, 1), ("SDS", 0x5F, 1), ("ADD", 0x60, 1), ("SUB", 0x61, 1), ("DIV", 0x62, 1), ("MUL", 0x63, 1),
                      ("ABS", 0x64, 1), ("NEG", 0x65, 1), ("FLOOR", 0x66, 1), ("CEILING", 0x67, 1), ("ROUND", 0x68, 4), ("NROUND", 0x6C, 4), ("WCVTF", 0x70, 1), ("DELTAP2", 0x71, 1),
                      ("DELTAP3", 0x72, 1), ("DELTAC1", 0x73, 1), ("DELTAC2", 0x74, 1), ("DELTAC3", 0x75, 1), ("SROUND", 0x76, 1), ("S45ROUND", 0x77, 1), ("JROT", 0x78, 1),
                      ("JROF", 0x79, 1), ("ROFF", 0x7A, 1), ("RUTG", 0x7C, 1), ("RDTG", 0x7D, 1), ("SANGW", 0x7E, 1), ("AA", 0x7F, 1), ("FLIPPT", 0x80, 1), ("FLIPRGON", 0x81, 1),
                      ("FLIPRGOFF", 0x82, 1), ("SCANCTRL", 0x85, 1), ("SDPVTL", 0x86, 2), ("GETINFO", 0x88, 1), ("IDEF", 0x89, 1), ("ROLL", 0x8A, 1), ("MAX", 0x8B, 1), ("MIN", 0x8C, 1),
                      ("SCANTYPE", 0x8D, 1), ("INSTCTRL", 0x8E, 1)):
    for k in range(n):
        NAMES[base + k] = "%s[%d]" % (name, k) if n > 1 else name
for k in range(32):
    NAMES[0xC0 + k] = "MDRP[%s]" % format(k, "05b")
    NAMES[0xE0 + k] = "MIRP[%s]" % format(k, "05b")


def main():
    f = TTFont(sys.argv[1])
    code = int(sys.argv[2])
    g = f["glyf"][f.getBestCmap()[code]]
    first = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    last = int(sys.argv[4]) if len(sys.argv) > 4 else 10**6
    ops = nonpush(g.program.getBytecode())
    for k, (off, op, pend) in enumerate(ops, 1):
        if first <= k <= last:
            print("#%-3d %5d %-14s %s" % (k, off, NAMES.get(op, "0x%02X" % op), pend))
    print("points", len(g.coordinates) if not g.isComposite() else "composite")


if __name__ == "__main__":
    main()
