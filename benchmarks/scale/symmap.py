# Maps perf sample addresses (file offsets) to functions using the compiler's own
# symbol table appended after the code.
import struct, re, sys
exe = sys.argv[1]
d = open(exe, 'rb').read()
table = None
for ts in range(len(d) - 5000000, len(d) - 32):
    e = struct.unpack_from('<I', d, ts)[0]
    if 1 < e < 50000 and struct.unpack_from('<I', d, ts + 4 + 8)[0] == 4 + e * 24:
        table = ts; count = e; break
assert table is not None, "no table"
funcs = []
for k in range(count):
    rel, size, noff, nlen, lrow, lcount = struct.unpack_from('<IIIIII', d, table + 4 + k * 24)
    start = (table + rel) & 0xFFFFFFFF if rel >= 0x80000000 else table + rel
    if rel >= 0x80000000:
        start = table - (0x100000000 - rel)
    name = d[table + noff:table + noff + nlen].decode(errors='replace')
    funcs.append((start, size, name))
funcs.sort()
def lookup(addr):
    lo, hi = 0, len(funcs)
    while lo < hi:
        mid = (lo + hi) // 2
        if funcs[mid][0] <= addr: lo = mid + 1
        else: hi = mid
    if lo == 0: return '?'
    s, sz, n = funcs[lo - 1]
    return n if addr < s + sz + 16 else f'?({n}+{addr - s})'
totals = {}
for line in open(sys.argv[2]):
    m = re.match(r'\s*([\d.]+)%.*\[\.\]\s+0x([0-9a-f]+)', line)
    if not m: continue
    pct, addr = float(m.group(1)), int(m.group(2), 16)
    totals[lookup(addr)] = totals.get(lookup(addr), 0) + pct
for n, p in sorted(totals.items(), key=lambda x: -x[1])[:20]:
    print(f'{p:6.2f}%  {n}')
