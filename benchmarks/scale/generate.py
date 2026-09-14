# Generates a many-module neper program for measuring the compiler at scale.
#
#   python generate.py OUT_DIR --modules 2000 --lines 2000000 [--seed 1]
#
# The program is a DAG of modules. Each module declares a record type and a
# log-normally distributed number of functions; a function loops over an integer
# range, branches on the running value, mixes in a field of the record, and calls one
# or two functions of modules earlier in the order, so calls cross module boundaries
# and nothing is dead. `main` folds every module's root through a checksum and prints
# it, so the executable does work proportional to the program and its answer can be
# checked (the same generator arguments always yield the same program and answer).
#
# It is a generated program, and says so. What it is for is the shape a real one has
# that a single big file does not: thousands of files of unequal size, an import graph,
# and calls that cross it.
import argparse
import math
import os
import random

parser = argparse.ArgumentParser()
parser.add_argument('out')
parser.add_argument('--modules', type=int, default=2000)
parser.add_argument('--lines', type=int, default=2_000_000)
parser.add_argument('--seed', type=int, default=1)
parser.add_argument('--fanin', type=int, default=3, help='imports per module (at most)')
args = parser.parse_args()
rng = random.Random(args.seed)

LINES_PER_FUNCTION = 12  # what one generated function costs, measured below
FIXED_PER_MODULE = 9

functions_total = max(args.modules, (args.lines - args.modules * FIXED_PER_MODULE) // LINES_PER_FUNCTION)
# Log-normal module sizes, then scaled so the total lands on the request.
weights = [rng.lognormvariate(0.0, 0.9) for _ in range(args.modules)]
scale = functions_total / sum(weights)
counts = [max(1, int(round(w * scale))) for w in weights]

src = os.path.join(args.out, 'src')
os.makedirs(src, exist_ok=True)
names = ['m%04d' % i for i in range(args.modules)]
imports_of = []
params = {}  # (module, k) -> (m1, m2, m3, callee)
total_lines = 0

for i, name in enumerate(names):
    imports = sorted(rng.sample(range(i), min(args.fanin, i))) if i > 0 else []
    imports_of.append(imports)
    out = []
    out.append('// Module %d of %d: %d functions.' % (i, args.modules, counts[i]))
    for j in imports:
        out.append('use %s' % names[j])
    out.append('')
    out.append('type Rec = struct {')
    out.append('    a: i64,')
    out.append('    b: i64,')
    out.append('}')
    out.append('')
    for k in range(counts[i]):
        callee = None
        if imports:
            j = rng.choice(imports)
            callee = (names[j], rng.randrange(counts[j]))
        m1, m2, m3 = rng.randrange(3, 97), rng.randrange(1, 1000), rng.randrange(1, 64)
        params[(i, k)] = (m1, m2, m3, callee)
        out.append('fn job%d(n: i64) -> i64 {' % k)
        out.append('    var r = Rec { a: n, b: %di64 }' % m2)
        out.append('    var acc = 0i64')
        out.append('    var i = 0i64')
        out.append('    while i < %di64 {' % m3)
        out.append('        if (acc + i) %% %di64 == 0i64 { acc = acc + r.a } else { acc = acc + r.b }' % m1)
        out.append('        i = i + 1i64')
        out.append('    }')
        if callee is not None:
            out.append('    ret (acc + %s.job%d(n %% 1000i64)) & 1073741823i64' % callee)
        else:
            out.append('    ret acc & 1073741823i64')
        out.append('}')
        out.append('')
    text = '\n'.join(out) + '\n'
    total_lines += text.count('\n')
    open(os.path.join(src, name + '.e'), 'w', newline='\n').write(text)

# main: every module's f0 folded through a checksum, printed.
out = ['use e.os', 'use e.mem', 'use e.io', 'use e.str']
for name in names:
    out.append('use %s' % name)
out.append('')
out.append('fn main(a: *mem.Arena, args: []str) -> err {')
out.append('    var sum = 0i64')
for i, name in enumerate(names):
    out.append('    sum = (sum * 31i64 + %s.job0(%di64)) & 1073741823i64' % (name, i))
out.append('    let (b0, b0_error) = str.builder(a, 64usize)')
out.append('    if b0_error != ok { ret b0_error }')
out.append('    var b = b0')
out.append('    try str.push_i64(&b, sum)')
out.append('    try str.push(&b, "\\n")')
out.append('    try io.print(str.done(&b))')
out.append('    ret ok')
out.append('}')
text = '\n'.join(out) + '\n'
total_lines += text.count('\n')
open(os.path.join(src, 'main.e'), 'w', newline='\n').write(text)

# The answer, evaluated from the recorded parameters, so a build is checked against
# something the compiler had no hand in.
import sys
sys.setrecursionlimit(20000)
memo = {}
index_of = {n: i for i, n in enumerate(names)}
def f(i, k, n):
    key = (i, k, n)
    if key in memo:
        return memo[key]
    m1, m2, m3, callee = params[(i, k)]
    acc = 0
    for step in range(m3):
        acc = acc + (n if (acc + step) % m1 == 0 else m2)
    if callee is not None:
        acc = (acc + f(index_of[callee[0]], callee[1], n % 1000)) & 1073741823
    else:
        acc = acc & 1073741823
    memo[key] = acc
    return acc
answer = 0
for i in range(args.modules):
    answer = (answer * 31 + f(i, 0, i)) & 1073741823
open(os.path.join(args.out, 'expected.txt'), 'w', newline='\n').write('%d\n' % answer)
sizes = sorted(counts)
print('modules %d, functions %d, lines %d, module sizes: min %d, median %d, max %d lines; expected %d' % (
    args.modules, sum(counts), total_lines, sizes[0] * LINES_PER_FUNCTION + FIXED_PER_MODULE,
    sizes[len(sizes) // 2] * LINES_PER_FUNCTION + FIXED_PER_MODULE, sizes[-1] * LINES_PER_FUNCTION + FIXED_PER_MODULE, answer))
