# Who calls a function, from `perf script` stacks: the immediate callers of NAME with
# the share of NAME's samples each accounts for.
#   python3 perf_callers.py neper-prof stacks.txt NAME [depth]
import struct, re, sys
exe = sys.argv[1]
d = open(exe, 'rb').read()
table = None
for ts in range(len(d) - 5000000, len(d) - 32):
    e = struct.unpack_from('<I', d, ts)[0]
    if 1 < e < 50000 and struct.unpack_from('<I', d, ts + 4 + 8)[0] == 4 + e * 24:
        table = ts; count = e; break
funcs = []
for k in range(count):
    rel, size, noff, nlen, lrow, lcount = struct.unpack_from('<IIIIII', d, table + 4 + k * 24)
    start = table + rel if rel < 0x80000000 else table - (0x100000000 - rel)
    funcs.append((start, size, d[table + noff:table + noff + nlen].decode(errors='replace')))
funcs.sort()
def lookup(addr):
    addr -= 0x400000
    lo, hi = 0, len(funcs)
    while lo < hi:
        mid = (lo + hi) // 2
        if funcs[mid][0] <= addr: lo = mid + 1
        else: hi = mid
    if lo == 0: return '?'
    s, sz, n = funcs[lo - 1]
    return n if addr < s + sz + 16 else '?'
name = sys.argv[3]
depth = int(sys.argv[4]) if len(sys.argv) > 4 else 1
callers = {}
total = 0
stack = []
def flush():
    global total
    if not stack: return
    names = [lookup(a) for a in stack]
    if names and names[0] == name:
        total += 1
        chain = ' <- '.join(names[1:1 + depth])
        callers[chain] = callers.get(chain, 0) + 1
    stack.clear()
for line in open(sys.argv[2], errors='replace'):
    m = re.match(r'\s*([0-9a-f]+)\s', line)
    if m and line.startswith((' ', '\t')):
        stack.append(int(m.group(1), 16))
    elif line.strip() == '':
        flush()
flush()
print(f'{total} self samples in {name}')
for c, n in sorted(callers.items(), key=lambda x: -x[1])[:25]:
    print(f'{100.0 * n / max(total, 1):6.2f}%  {c}')
