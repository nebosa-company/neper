# Inclusive (self+callees) time per function from `perf script` stacks, mapped through
# the compiler's own symbol table like symmap.py. Each function counts once per sample,
# so recursion does not inflate it.
#   perf script -i data.perf -F ip,sym --no-demangle > stacks.txt   (with -g recording)
#   python3 perf_inclusive.py neper-prof stacks.txt [top] [base]
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
    start = table + rel if rel < 0x80000000 else table - (0x100000000 - rel)
    name = d[table + noff:table + noff + nlen].decode(errors='replace')
    funcs.append((start, size, name))
funcs.sort()
base = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x400000
def lookup(addr):
    addr -= base
    lo, hi = 0, len(funcs)
    while lo < hi:
        mid = (lo + hi) // 2
        if funcs[mid][0] <= addr: lo = mid + 1
        else: hi = mid
    if lo == 0: return '?'
    s, sz, n = funcs[lo - 1]
    return n if addr < s + sz + 16 else '?'
samples = 0
incl = {}
selfc = {}
stack = []
def flush():
    global samples
    if not stack: return
    samples += 1
    seen = set()
    for i, a in enumerate(stack):
        n = lookup(a)
        if i == 0: selfc[n] = selfc.get(n, 0) + 1
        if n not in seen:
            seen.add(n)
            incl[n] = incl.get(n, 0) + 1
    stack.clear()
for line in open(sys.argv[2], errors='replace'):
    m = re.match(r'\s*([0-9a-f]+)\s', line)
    if m and line.startswith((' ', '\t')):
        stack.append(int(m.group(1), 16))
    elif line.strip() == '':
        flush()
flush()
top = int(sys.argv[3]) if len(sys.argv) > 3 else 40
print(f'{samples} samples')
for n, c in sorted(incl.items(), key=lambda x: -x[1])[:top]:
    print(f'{100.0 * c / samples:6.2f}% incl {100.0 * selfc.get(n, 0) / samples:6.2f}% self  {n}')
