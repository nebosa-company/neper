"""Reference and fixture generator for e.algo.collect (L022).

  python scripts/collect_reference.py

Python statements of petcow's Terraform collection functions (src/interp.rs) on plain Python objects: flatten,
distinct, compact, slice, element, one, matchkeys, zipmap, transpose, setproduct, range, sum, product, min, max, pow,
log, signum, parseint. Equality is by value (1 equals 1.0, objects by key set, a bool is not a number). Writes
tests/selfhost/fixtures/link/algo_collect/src/main.e from scripts/collect_fixture_template.e.
"""
import itertools
import json
import math
import pathlib
import random

INF = float('inf')
MAX_RANGE = 1000000


def key(v):
    if v is None:
        return ('n',)
    if isinstance(v, bool):
        return ('b', v)
    if isinstance(v, (int, float)):
        return ('d', float(v))
    if isinstance(v, str):
        return ('s', v)
    if isinstance(v, list):
        return ('l', tuple(key(x) for x in v))
    return ('o', frozenset((k, key(x)) for k, x in v.items()))


def flatten(v):
    out = []
    for x in v:
        if isinstance(x, list):
            out.extend(flatten(x))
        else:
            out.append(x)
    return out


def distinct(v):
    out, seen = [], set()
    for x in v:
        if key(x) not in seen:
            seen.add(key(x))
            out.append(x)
    return out


def dumps(v):
    return json.dumps(v, separators=(',', ':'), ensure_ascii=False)


def fdiv(num, den):
    if math.isnan(num) or math.isnan(den):
        return math.nan
    if den == 0:
        if num == 0:
            return math.nan
        return math.copysign(INF, num) * math.copysign(1, den)
    if math.isinf(num) and math.isinf(den):
        return math.nan
    return num / den


def ln(x):
    if x < 0 or math.isnan(x):
        return math.nan
    if x == 0:
        return -INF
    return math.log(x)


class Raw(str):
    """Result text written as it is (an error marker or a number's repr), not JSON-encoded."""


def op_line(op, args, result):
    return '%s %s => %s' % (op, ' | '.join(dumps(a) for a in args), result if isinstance(result, Raw) else dumps(result))


def err(name):
    return Raw('E:' + name)


def L_flatten(v):
    return op_line('F', [v], flatten(v))


def L_distinct(v):
    return op_line('D', [v], distinct(v))


def L_compact(v):
    return op_line('C', [v], [x for x in v if x != ''] if True else v)


def L_slice(v, s, e):
    if s < 0 or e < s or e > len(v):
        return op_line('L', [v, s, e], err('OutOfRange'))
    return op_line('L', [v, s, e], v[s:e])


def L_element(v, i):
    if not v:
        return op_line('E', [v, i], err('Empty'))
    if i < 0:
        return op_line('E', [v, i], err('NegativeIndex'))
    return op_line('E', [v, i], v[i % len(v)])


def L_one(v):
    if len(v) > 1:
        return op_line('O', [v], err('LengthMismatch'))
    return op_line('O', [v], v[0] if v else None)


def L_matchkeys(values, keys, search):
    if len(values) != len(keys):
        return op_line('M', [values, keys, search], err('LengthMismatch'))
    skeys = [key(s) for s in search]
    return op_line('M', [values, keys, search], [v for v, k in zip(values, keys) if key(k) in skeys])


def L_zipmap(keys, values):
    if len(keys) != len(values):
        return op_line('Z', [keys, values], err('LengthMismatch'))
    if not all(isinstance(k, str) for k in keys):
        return op_line('Z', [keys, values], err('Invalid'))
    out = {}
    for k, v in zip(keys, values):
        out[k] = v
    return op_line('Z', [keys, values], out)


def L_transpose(m):
    out = {}
    for k, v in m.items():
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            return op_line('T', [m], err('Invalid'))
        for x in v:
            out.setdefault(x, []).append(k)
    return op_line('T', [m], {k: sorted(out[k]) for k in sorted(out)})


def L_setproduct(*lists):
    if len(lists) < 2:
        return op_line('P', list(lists), err('TooFew'))
    total = 1
    for l in lists:
        if not l:
            return op_line('P', list(lists), [])
        total *= len(l)
    if total > MAX_RANGE:
        return op_line('P', list(lists), err('TooLarge'))
    return op_line('P', list(lists), [list(c) for c in itertools.product(*lists)])


def L_range(start, limit, step):
    if step == 0:
        return op_line('R', [start, limit, step], err('ZeroStep'))
    n = 0
    if step > 0 and start < limit:
        n = -(-(limit - start) // step)
    if step < 0 and start > limit:
        n = -(-(start - limit) // -step)
    if n > MAX_RANGE:
        return op_line('R', [start, limit, step], err('TooLarge'))
    return op_line('R', [start, limit, step], [start + i * step for i in range(n)])


def numeric(v):
    return all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v)


def L_numbers(op, v, fn):
    if not v:
        return op_line(op, [v], err('Empty'))
    if not numeric(v):
        return op_line(op, [v], err('Invalid'))
    return op_line(op, [v], Raw(repr(float(fn(v)))))


def L_pow(x, y):
    return op_line('W', [x, y], Raw(repr(math.pow(x, y))))


def L_log(n, b):
    r = fdiv(ln(float(n)), ln(float(b)))
    if math.isnan(r) or math.isinf(r):
        return op_line('G', [n, b], err('NotFinite'))
    return op_line('G', [n, b], Raw(repr(r)))


def L_signum(x):
    return op_line('I', [x], (x > 0) - (x < 0))


def L_parseint(s, base):
    if base < 2 or base > 36:
        return op_line('J', [s, base], err('BadBase'))
    t = s.strip(' \t\n\r\x0b\x0c')
    neg = False
    if t[:1] == '+':
        t = t[1:]
    elif t[:1] == '-':
        neg = True
        t = t[1:]
    digits = '0123456789abcdefghijklmnopqrstuvwxyz'
    if not t or any(c.lower() not in digits[:base] for c in t):
        return op_line('J', [s, base], err('NotInteger'))
    v = 0
    for c in t:
        v = v * base + digits.index(c.lower())
    if neg:
        v = -v
    if v < -(1 << 63) or v >= (1 << 63):
        return op_line('J', [s, base], err('NotInteger'))
    return op_line('J', [s, base], v)


WORDS = ['a', 'b', 'c', 'd', '', 'x y', 'é', '日本']


def scalar(rng):
    r = rng.random()
    if r < 0.2:
        return rng.randint(-3, 3)
    if r < 0.3:
        return rng.choice([0.5, 1.0, 2.5, -1.5])
    if r < 0.4:
        return rng.choice([True, False, None])
    return rng.choice(WORDS)


def nested(rng, depth=0):
    out = []
    for _ in range(rng.randint(0, 4)):
        if depth < 3 and rng.random() < 0.3:
            out.append(nested(rng, depth + 1))
        elif rng.random() < 0.1:
            out.append({rng.choice('ab'): scalar(rng)})
        else:
            out.append(scalar(rng))
    return out


def main():
    rng = random.Random(2205)
    lines = []
    # petcow's assertions
    assert [x for x in ['x', '', 'y'] if x != ''] == ['x', 'y']
    assert [1, 3, 5, 7] == list(range(1, 8, 2)) and list(range(3, 0, -1)) == [3, 2, 1]
    lines += [L_flatten([[1, [2]], 3, []]), L_flatten([]), L_flatten([[], [[]]]), L_distinct([1, 1.0, '1', True, None, None, {'a': 1}, {'a': 1.0}, [1], [1.0]]),
              L_compact(['x', '', 'y', None, 0]), L_slice(['a', 'b', 'c', 'd'], 1, 3), L_slice(['a'], 0, 2), L_slice(['a'], 1, 0), L_slice(['a'], -1, 1), L_slice([], 0, 0),
              L_element(['a', 'b', 'c'], 4), L_element([], 0), L_element(['a'], -1), L_one([]), L_one([7]), L_one([1, 2]),
              L_zipmap(['k'], [9]), L_zipmap(['a', 'b'], [1]), L_zipmap(['a', 'a'], [1, 2]), L_zipmap([1], [2]),
              L_transpose({'a': ['x', 'y'], 'b': ['x']}), L_transpose({'a': [1]}), L_transpose({'a': 'x'}), L_transpose({}),
              L_setproduct([1, 2], ['a', 'b']), L_setproduct([1], [2], [3, 4]), L_setproduct([1]), L_setproduct([1], []),
              L_range(0, 3, 1), L_range(1, 8, 2), L_range(3, 0, -1), L_range(0, 10, 0), L_range(0, 1000001, 1), L_range(0, 1000000, 1) if False else L_range(0, 5, 10), L_range(5, 0, 1),
              L_numbers('S', [1, 2, 3], sum), L_numbers('S', [], sum), L_numbers('S', ['a'], sum), L_numbers('Q', [2, 3, 4], math.prod), L_numbers('N', [3, 1, 2], min), L_numbers('X', [3, 1, 2.5], max),
              L_pow(2, 10), L_pow(2, 0.5), L_pow(10, -2), L_log(10, 10), L_log(1, 10), L_log(0, 10), L_log(-1, 10), L_log(8, 2), L_log(5, 1), L_log(5, 0), L_log(0.5, 0.25),
              L_signum(-5), L_signum(0), L_signum(2.5), L_signum(-0.0),
              L_parseint('ff', 16), L_parseint('101', 2), L_parseint(' 42 ', 10), L_parseint('-7f', 16), L_parseint('+z', 36), L_parseint('9', 8), L_parseint('', 10), L_parseint('-', 10),
              L_parseint('1', 1), L_parseint('1', 37), L_parseint('9223372036854775807', 10), L_parseint('9223372036854775808', 10), L_parseint('-9223372036854775808', 10), L_parseint('1_0', 10)]
    for _ in range(300):
        v = nested(rng)
        lines.append(L_flatten(v))
        flat = [x for x in flatten(v)]
        pool = [scalar(rng) for _ in range(rng.randint(0, 8))]
        lines.append(L_distinct(pool + pool[:2]))
        lines.append(L_compact([x for x in pool if not isinstance(x, (dict, list))]))
        n = len(pool)
        lines.append(L_slice(pool, rng.randint(-1, n), rng.randint(-1, n + 1)))
        lines.append(L_element(pool, rng.randint(-1, 2 * n + 2)))
        lines.append(L_one(pool[:rng.randint(0, 2)]))
        keys = [rng.choice(WORDS) for _ in range(len(pool) + rng.choice([0, 0, 0, 1]))]
        lines.append(L_matchkeys(pool, keys, [rng.choice(WORDS) for _ in range(rng.randint(0, 3))]))
        zk = [rng.choice(WORDS[:5]) for _ in range(rng.randint(0, 5))]
        lines.append(L_zipmap(zk, [scalar(rng) for _ in zk]))
        tm = {rng.choice('abcde'): [rng.choice('xyz') for _ in range(rng.randint(0, 3))] for _ in range(rng.randint(0, 4))}
        lines.append(L_transpose(tm))
        lists = [[scalar(rng) for _ in range(rng.randint(0, 3))] for _ in range(rng.randint(2, 4))]
        lines.append(L_setproduct(*lists))
        lines.append(L_range(rng.randint(-10, 10), rng.randint(-10, 10), rng.choice([1, 2, 3, -1, -2, -3, 0, 5])))
        nums = [rng.choice([rng.randint(-50, 50), rng.randint(-5, 5) / 2]) for _ in range(rng.randint(0, 6))]
        lines.append(L_numbers('S', nums, sum))
        lines.append(L_numbers('Q', nums, math.prod))
        lines.append(L_numbers('N', nums, min))
        lines.append(L_numbers('X', nums, max))
        lines.append(L_pow(rng.choice([2, 3, 0.5, 10, 1.5]), rng.choice([0, 1, 2, -1, 0.5, 3, 10])))
        lines.append(L_log(rng.choice([0, 1, 2, 8, 100, -3, 0.5]), rng.choice([2, 10, 0.5, 1, 0, -2, 3])))
        lines.append(L_signum(rng.choice([-2, 0, 3, -0.5, 7.5])))
        base = rng.choice([2, 8, 10, 16, 36, 1, 40])
        text = ''.join(rng.choice('0123456789abcxzZ+- \t_') for _ in range(rng.randint(0, 6)))
        lines.append(L_parseint(text, base))
    here = pathlib.Path(__file__).resolve().parent
    chunks = ['"' + '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"') for l in lines[i:i + 60]) + '\\n"' for i in range(0, len(lines), 60)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    template = (here / 'collect_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_collect' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', len(lines), 'cases in', len(chunks), 'chunks')


main()
