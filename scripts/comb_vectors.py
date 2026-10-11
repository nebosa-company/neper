"""Independent oracle for e.parse.comb (L131), built on parsy.

Two grammars are written in parsy and as Neper combinators; random valid inputs and
random corruptions of them (deleted, inserted, replaced characters and truncations) are
parsed by parsy, and the fixture must agree on the result: the value of an arithmetic
expression (mod 2**64), or the offset parsy reports as its furthest failure; for the
key/value grammar, the event stream or the failure offset. Valid arithmetic inputs
without unary minus are also checked against Python's own `eval` (with ^ as **).

Usage: python scripts/comb_vectors.py --emit-expr | --emit-kv | (self check)
parsy must be importable (python -m pip install --target DIR parsy; PYTHONPATH=DIR).
"""
import random
import re
import sys

from parsy import ParseError, regex, string, forward_declaration, seq

MASK = (1 << 64) - 1
SPACES = regex(r'[ ]*')


def tok(p):
    return p << SPACES


def build_expr():
    expr = forward_declaration()
    number = tok(regex(r'[0-9]+').map(int))
    lparen, rparen = tok(string('(')), tok(string(')'))
    minus = tok(string('-'))
    atom = forward_declaration()
    paren = seq(lparen, expr, rparen).combine(lambda a, e, c: e)
    neg = (minus >> atom).map(lambda v: (-v) & MASK)
    atom.become(number | paren | neg)

    def chain_right(operand, op, apply):
        node = forward_declaration()
        tail = seq(op, node)
        node.become(seq(operand, tail.optional()).combine(
            lambda v, t: v if t is None else apply(v, t[1])))
        return node

    def chain_left(operand, op_choices):
        # op_choices: list of (parser, fn)
        step = None
        for p, fn in op_choices:
            alt = p.map(lambda _, fn=fn: fn)
            step = alt if step is None else step | alt
        return seq(operand, seq(step, operand).many()).combine(
            lambda first, rest: _fold(first, rest))

    def _fold(first, rest):
        acc = first
        for fn, v in rest:
            acc = fn(acc, v)
        return acc

    power = chain_right(atom, tok(string('^')), lambda a, b: _pow(a, b))
    term = chain_left(power, [(tok(string('*')), lambda a, b: (a * b) & MASK)])
    expr.become(chain_left(term, [(tok(string('+')), lambda a, b: (a + b) & MASK),
                                  (tok(string('-')), lambda a, b: (a - b) & MASK)]))
    return SPACES >> expr


def _pow(a, b):
    # b is a u64 here; Neper loops b times, so the oracle uses modular pow of the same count
    return pow(a, b, 1 << 64)


EXPR = build_expr()


def random_expr(rng, depth=0):
    r = rng.random()
    if depth > 3 or r < 0.3:
        return str(rng.randint(0, 99))
    if r < 0.45:
        return '(' + sp(rng) + random_expr(rng, depth + 1) + sp(rng) + ')'
    if r < 0.55:
        return '-' + sp(rng) + random_atom(rng, depth + 1)
    op = rng.choice(['+', '-', '*', '+', '-', '*', '^'])
    if op == '^':
        return random_atom(rng, depth + 1) + sp(rng) + '^' + sp(rng) + str(rng.randint(0, 5))
    return random_expr(rng, depth + 1) + sp(rng) + op + sp(rng) + random_expr(rng, depth + 1)


def random_atom(rng, depth):
    if rng.random() < 0.5:
        return str(rng.randint(0, 99))
    return '(' + random_expr(rng, depth + 1) + ')'


def sp(rng):
    return ' ' * rng.choice([0, 0, 1, 2])


def corrupt(rng, s):
    if not s:
        return s
    kind = rng.randrange(4)
    i = rng.randrange(len(s))
    junk = rng.choice('0123456789+-*^() xz#')
    if kind == 0:
        return s[:i] + s[i + 1:]
    if kind == 1:
        return s[:i] + junk + s[i:]
    if kind == 2:
        return s[:i] + junk + s[i + 1:]
    return s[:i]


def expr_cases():
    rng = random.Random(1311)
    cases = []
    inputs = ['', ' ', '1', '1 ', ' 1', '(1)', '((2))', '-3', '- 3', '--3', '2^3^2', '2 * 3 + 4', '2 + 3 * 4',
              '(2 + 3) * 4', '10 - 4 - 3', '2^', '1 +', '(1', '1)', '+1', '1 2', '0^0', '7^0', '3^-1', '(1+2)^2^2']
    inputs += [random_expr(rng) for _ in range(150)]
    inputs += [corrupt(rng, random_expr(rng)) for _ in range(150)]
    for s in inputs:
        try:
            v = EXPR.parse(s)
            if '-' not in s.replace(' ', '')[:0] and not re.search(r'(^|[(*^+\-])\s*-', s):
                try:
                    py = eval(s.replace('^', '**')) if s.strip() else None
                except SyntaxError:
                    py = None
                if py is not None and 0 <= py < (1 << 62):
                    assert py == v, (s, py, v)
            cases.append((s, 'v:%d' % v))
        except ParseError as e:
            cases.append((s, 'e:%d' % e.index))
    return cases


# ---- key/value grammar: `[ key = value (, key = value)* ]` ----
def build_kv():
    ident = regex(r'[a-z][a-z0-9_]*')
    number = regex(r'[0-9]+')
    quoted = string('"') >> regex(r'[^"]*') << string('"')
    pair = seq(tok(ident), tok(string('=')) >> tok(number.map(lambda t: ('N', t)) | quoted.map(lambda t: ('S', t))))
    items = pair.sep_by(tok(string(',')))
    return SPACES >> tok(string('[')) >> items << tok(string(']'))


KV = build_kv()


def kv_summary(parsed):
    out = []
    for key, (kind, value) in parsed:
        out.append('K:%s;%s:%s;P' % (key, kind, value))
    return '|'.join(out)


def random_kv(rng):
    n = rng.randint(0, 4)
    parts = []
    for _ in range(n):
        key = ''.join(rng.choice('abcdefgh_') for _ in range(rng.randint(1, 5)))
        key = 'k' + key
        value = str(rng.randint(0, 9999)) if rng.random() < 0.5 else '"' + ''.join(rng.choice('xyz 12') for _ in range(rng.randint(0, 4))) + '"'
        parts.append(key + sp(rng) + '=' + sp(rng) + value)
    return '[' + sp(rng) + (',' + sp(rng)).join(parts) + sp(rng) + ']'


def kv_cases():
    rng = random.Random(2077)
    inputs = ['[]', '[ ]', '[a=1]', '[a=1,b="x"]', '[a=]', '[a=1,]', '[', 'a=1', '', '[a=1] x', '[a="open]', '[=1]']
    inputs += [random_kv(rng) for _ in range(80)]
    inputs += [corrupt(rng, random_kv(rng)) for _ in range(120)]
    cases = []
    for s in inputs:
        try:
            cases.append((s, 'v:' + kv_summary(KV.parse(s))))
        except ParseError as e:
            cases.append((s, 'e:%d' % e.index))
    return cases


def emit(cases):
    for s, r in cases:
        assert '~' not in s and '\n' not in s
        print(s + '~' + r)


if __name__ == '__main__':
    if '--emit-expr' in sys.argv:
        emit(expr_cases())
    elif '--emit-kv' in sys.argv:
        emit(kv_cases())
    else:
        e, k = expr_cases(), kv_cases()
        print('comb_vectors: %d expression cases (%d values), %d key/value cases' %
              (len(e), sum(1 for _, r in e if r[0] == 'v'), len(k)))
