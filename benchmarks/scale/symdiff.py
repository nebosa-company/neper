# Which functions differ between two images of the same size, by the symbol table
# each image carries after its code.  python symdiff.py a.exe b.exe
import struct, sys

def table(d):
    for ts in range(len(d) - 5000000, len(d) - 32):
        e = struct.unpack_from('<I', d, ts)[0]
        if 1 < e < 50000 and struct.unpack_from('<I', d, ts + 4 + 8)[0] == 4 + e * 24:
            funcs = []
            for k in range(e):
                rel, size, noff, nlen, lrow, lcount = struct.unpack_from('<IIIIII', d, ts + 4 + k * 24)
                start = ts + rel if rel < 0x80000000 else ts - (0x100000000 - rel)
                funcs.append((start, size, d[ts + noff:ts + noff + nlen].decode(errors='replace')))
            return sorted(funcs)
    raise SystemExit('no table')

a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
fa = table(a)
fb = {n: (s, z) for s, z, n in table(b)}
shown = 0
for s, z, n in fa:
    if n in fb:
        s2, z2 = fb[n]
        if z != z2 or a[s:s + z] != b[s2:s2 + z2]:
            print(f'{n}: size {z} vs {z2}, at {s:#x} vs {s2:#x}')
            shown += 1
    else:
        print(f'{n}: only in first')
        shown += 1
    if shown > 40: break
print(f'{len(fa)} functions')
