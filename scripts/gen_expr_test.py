"""Generate tests/selfhost/fixtures/link/algo_expr/src/main.e (L157, D2804).

There is no JEXL, SpEL or MVEL engine on this host (no JVM), so the reference is an
independent Python implementation of the language as `e.algo.expr` documents it: its own
tokenizer, precedence-climbing parser and evaluator over the same value model, and the same
host world (an object graph with properties and methods, global functions, a Denied method).
Vectors are hand-written expressions covering every operator, literal and built-in plus
random trees rendered with random spacing and parentheses; each carries the strict flag
and step limit it runs under and an expected result or error name. Float results compare
by bit pattern. Step counts and depth limits are replicated exactly.
"""
import random
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(157)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_expr' / 'src' / 'main.e'
I64_MAX = (1 << 63) - 1
I64_MIN = -(1 << 63)


class Err(Exception):
    def __init__(self, name):
        self.name = name


# ---- values: None, bool, int, float, str, list, dict (ordered), Obj ----
class Obj:
    def __init__(self, ident):
        self.ident = ident


USER = Obj(1)
ADDRESS = Obj(2)
PROPS = {
    1: {'name': 'Ann', 'age': 30, 'active': True, 'score': 2.5, 'tags': ['a', 'b'], 'address': ADDRESS, 'manager': None},
    2: {'city': 'Paris', 'zip': '75001', 'lines': ['x', 'y']},
}
SCOPE = {'x': 7, 'y': 2, 'f': 2.5, 's': 'hello', 'e': '', 't': True, 'n': None, 'items': [1, 2, 3],
         'm': {'a': 1, 'b': {'c': 2}}, 'user': USER, 'words': ['foo', 'bar'], 'big': I64_MAX, 'neg': -5, 'z': 0, 'half': 0.5}


def host_get(obj, name):
    props = PROPS[obj.ident]
    if name in props:
        return props[name], True
    return None, False


def truthy(v):
    if v is None:
        return False
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return v != 0
    if isinstance(v, float):
        return v != 0.0 and v == v
    if isinstance(v, (str, list, dict)):
        return len(v) > 0
    return True


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def equals(x, y):
    if is_number(x) and is_number(y):
        return x == y
    if x is None or y is None:
        return x is None and y is None
    if isinstance(x, bool) or isinstance(y, bool):
        return isinstance(x, bool) and isinstance(y, bool) and x == y
    if isinstance(x, str) and isinstance(y, str):
        return x == y
    if isinstance(x, list) and isinstance(y, list):
        return len(x) == len(y) and all(equals(a, b) for a, b in zip(x, y))
    if isinstance(x, dict) and isinstance(y, dict):
        return len(x) == len(y) and all(k in y and equals(v, y[k]) for k, v in x.items())
    if isinstance(x, Obj) and isinstance(y, Obj):
        return x.ident == y.ident
    return False


def fmt_float(f):
    if f == int(f) and abs(f) < 1e15:
        return '%d.0' % int(f)
    return repr(f)


def text_of(v, depth=0):
    if depth > 32:
        raise Err('Limit')
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return fmt_float(v)
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        return '[' + ', '.join(text_of(i, depth + 1) for i in v) + ']'
    if isinstance(v, dict):
        return '{' + ', '.join('%s=%s' % (k, text_of(i, depth + 1)) for k, i in v.items()) + '}'
    return '#%d' % v.ident


def check_i64(v):
    if v > I64_MAX or v < I64_MIN:
        raise Err('Overflow')
    return v


def trunc_div_rem(a, b):
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q, a - q * b


# ---- tokenizer ----
PUNCT2 = ['&&', '||', '==', '!=', '<=', '>=', '?.', '?[', '??', '?:', '=~', '!~', '=^', '=$', '..']


def name_start(c):
    return c.isalpha() and c.isascii() or c in '_$'


def name_char(c):
    return name_start(c) or c.isdigit() and c.isascii()


def lex(src, limits):
    toks = []
    i = 0
    while i < len(src):
        c = src[i]
        if c in ' \t\r\n':
            i += 1
            continue
        t = {'start': i}
        prev_punct = not toks or toks[-1]['kind'] == 'punct'
        if c.isdigit() or (c == '.' and i + 1 < len(src) and src[i + 1].isdigit() and prev_punct):
            j = i
            is_float = False
            while j < len(src) and src[j].isdigit():
                j += 1
            if j < len(src) and src[j] == '.' and not (j + 1 < len(src) and src[j + 1] == '.') and not (j + 1 < len(src) and name_start(src[j + 1])):
                is_float = True
                j += 1
                while j < len(src) and src[j].isdigit():
                    j += 1
            if j < len(src) and src[j] in 'eE':
                k = j + 1
                if k < len(src) and src[k] in '+-':
                    k += 1
                if k < len(src) and src[k].isdigit():
                    is_float = True
                    while k < len(src) and src[k].isdigit():
                        k += 1
                    j = k
            text = src[i:j]
            if is_float:
                t['kind'] = 'float'
                t['value'] = float(text)
            else:
                v = int(text)
                if v > I64_MAX:
                    raise Err('Overflow')
                t['kind'] = 'int'
                t['value'] = v
                t['text'] = text
            if j < len(src) and src[j] in 'Ll' and not (j + 1 < len(src) and name_char(src[j + 1])):
                j += 1
            i = j
        elif c in '\'"':
            q = c
            j = i + 1
            buf = []
            while j < len(src) and src[j] != q:
                ch = src[j]
                if ch == '\\':
                    j += 1
                    if j >= len(src):
                        raise Err('Syntax')
                    e = src[j]
                    if e == 'n':
                        ch = '\n'
                    elif e == 't':
                        ch = '\t'
                    elif e == 'r':
                        ch = '\r'
                    elif e == 'u':
                        if j + 4 >= len(src):
                            raise Err('Syntax')
                        try:
                            cp = int(src[j + 1:j + 5], 16)
                        except ValueError:
                            raise Err('Syntax')
                        buf.append(chr(cp))
                        j += 5
                        continue
                    else:
                        ch = e
                buf.append(ch)
                j += 1
                if len(''.join(buf).encode('utf-8')) > limits['max_string']:
                    raise Err('Limit')
            if j >= len(src):
                raise Err('Syntax')
            t['kind'] = 'str'
            t['text'] = ''.join(buf)
            i = j + 1
        elif name_start(c):
            j = i
            while j < len(src) and name_char(src[j]):
                j += 1
            t['kind'] = 'name'
            t['text'] = src[i:j]
            i = j
        else:
            n = 1
            if src[i:i + 2] in PUNCT2:
                n = 2
            t['kind'] = 'punct'
            t['text'] = src[i:i + n]
            i += n
        toks.append(t)
    toks.append({'kind': 'end', 'start': len(src)})
    return toks


# ---- parser (precedence climbing; its own implementation) ----
class Parser:
    def __init__(self, toks, max_depth):
        self.t = toks
        self.i = 0
        self.depth = 0
        self.max_depth = max_depth

    def punct(self, s):
        t = self.t[self.i]
        return t['kind'] == 'punct' and t['text'] == s

    def word(self, s):
        t = self.t[self.i]
        return t['kind'] == 'name' and t['text'] == s

    def expr(self):
        if self.depth >= self.max_depth:
            raise Err('Limit')
        self.depth += 1
        r = self.ternary()
        self.depth -= 1
        return r

    def ternary(self):
        cond = self.logical_or()
        if self.punct('?:'):
            self.i += 1
            return ('elvis', cond, self.ternary())
        if self.punct('??'):
            self.i += 1
            return ('coalesce', cond, self.ternary())
        if self.punct('?'):
            self.i += 1
            yes = self.ternary()
            if not self.punct(':'):
                raise Err('Syntax')
            self.i += 1
            return ('ternary', cond, yes, self.ternary())
        return cond

    def logical_or(self):
        left = self.logical_and()
        while self.punct('||') or self.word('or'):
            self.i += 1
            left = ('or', left, self.logical_and())
        return left

    def logical_and(self):
        left = self.equality()
        while self.punct('&&') or self.word('and'):
            self.i += 1
            left = ('and', left, self.equality())
        return left

    def equality(self):
        left = self.relational()
        while True:
            op = None
            if self.punct('==') or self.word('eq'):
                op = 'eq'
            elif self.punct('!=') or self.word('ne'):
                op = 'ne'
            elif self.punct('=~'):
                op = 'in'
            elif self.punct('!~'):
                op = 'nin'
            elif self.punct('=^'):
                op = 'starts'
            elif self.punct('=$'):
                op = 'ends'
            if op is None:
                return left
            self.i += 1
            left = ('bin', op, left, self.relational())

    def relational(self):
        left = self.range_()
        while True:
            op = None
            if self.punct('<') or self.word('lt'):
                op = 'lt'
            elif self.punct('<=') or self.word('le'):
                op = 'le'
            elif self.punct('>') or self.word('gt'):
                op = 'gt'
            elif self.punct('>=') or self.word('ge'):
                op = 'ge'
            if op is None:
                return left
            self.i += 1
            left = ('bin', op, left, self.range_())

    def range_(self):
        left = self.additive()
        if self.punct('..'):
            self.i += 1
            return ('range', left, self.additive())
        return left

    def additive(self):
        left = self.multiplicative()
        while self.punct('+') or self.punct('-'):
            op = 'add' if self.punct('+') else 'sub'
            self.i += 1
            left = ('bin', op, left, self.multiplicative())
        return left

    def multiplicative(self):
        left = self.unary()
        while True:
            op = None
            if self.punct('*'):
                op = 'mul'
            elif self.punct('/') or self.word('div'):
                op = 'div'
            elif self.punct('%') or self.word('mod'):
                op = 'mod'
            if op is None:
                return left
            self.i += 1
            left = ('bin', op, left, self.unary())

    def next_is_paren(self):
        t = self.t[self.i + 1]
        return t['kind'] == 'punct' and t['text'] == '('

    def unary(self):
        op = None
        if self.punct('!') or self.word('not'):
            op = 'not'
        if self.punct('-'):
            op = 'neg'
        if self.punct('+'):
            op = 'pos'
        if self.word('empty') and not self.next_is_paren():
            op = 'empty'
        if self.word('size') and not self.next_is_paren():
            op = 'size'
        if op:
            self.i += 1
            if self.depth >= self.max_depth:
                raise Err('Limit')
            self.depth += 1
            operand = self.unary()
            self.depth -= 1
            return ('unary', op, operand)
        return self.postfix()

    def args(self):
        out = []
        if not self.punct(')'):
            while True:
                out.append(self.expr())
                if len(out) > 32:
                    raise Err('Limit')
                if self.punct(','):
                    self.i += 1
                    continue
                break
        if not self.punct(')'):
            raise Err('Syntax')
        self.i += 1
        return out

    def postfix(self):
        base = self.primary()
        while True:
            if self.punct('.') or self.punct('?.'):
                safe = self.punct('?.')
                self.i += 1
                t = self.t[self.i]
                if t['kind'] != 'name':
                    raise Err('Syntax')
                self.i += 1
                if self.punct('('):
                    self.i += 1
                    base = ('method', base, t['text'], self.args(), safe)
                else:
                    base = ('prop', base, t['text'], safe)
            elif self.punct('[') or self.punct('?['):
                safe = self.punct('?[')
                self.i += 1
                idx = self.expr()
                if not self.punct(']'):
                    raise Err('Syntax')
                self.i += 1
                base = ('index', base, idx, safe)
            else:
                return base

    def primary(self):
        t = self.t[self.i]
        k = t['kind']
        if k == 'int' or k == 'float':
            self.i += 1
            return ('lit', t['value'])
        if k == 'str':
            self.i += 1
            return ('lit', t['text'])
        if k == 'name':
            self.i += 1
            if t['text'] == 'true':
                return ('lit', True)
            if t['text'] == 'false':
                return ('lit', False)
            if t['text'] == 'null':
                return ('lit', None)
            if self.punct('('):
                self.i += 1
                return ('call', t['text'], self.args())
            return ('var', t['text'])
        if k == 'punct' and t['text'] == '(':
            self.i += 1
            inner = self.expr()
            if not self.punct(')'):
                raise Err('Syntax')
            self.i += 1
            return inner
        if k == 'punct' and t['text'] == '[':
            self.i += 1
            items = []
            if not self.punct(']'):
                while True:
                    items.append(self.expr())
                    if len(items) > 64:
                        raise Err('Limit')
                    if self.punct(','):
                        self.i += 1
                        continue
                    break
            if not self.punct(']'):
                raise Err('Syntax')
            self.i += 1
            return ('list', items)
        if k == 'punct' and t['text'] == '{':
            self.i += 1
            pairs = []
            if not self.punct('}'):
                while True:
                    key = self.t[self.i]
                    if key['kind'] in ('str', 'name'):
                        kv = key['text']
                    elif key['kind'] == 'int':
                        kv = key['text']
                    else:
                        raise Err('Syntax')
                    self.i += 1
                    if not self.punct(':'):
                        raise Err('Syntax')
                    self.i += 1
                    pairs.append((kv, self.expr()))
                    if len(pairs) * 2 > 64:
                        raise Err('Limit')
                    if self.punct(','):
                        self.i += 1
                        continue
                    break
            if not self.punct('}'):
                raise Err('Syntax')
            self.i += 1
            return ('map', pairs)
        raise Err('Syntax')


# ---- evaluator ----
class Interp:
    def __init__(self, strict, max_steps, max_depth=64, max_string=65536, max_collection=10000):
        self.strict = strict
        self.max_steps = max_steps
        self.max_depth = max_depth
        self.max_string = max_string
        self.max_collection = max_collection
        self.steps = 0
        self.depth = 0

    def ev(self, n):
        self.steps += 1
        if self.max_steps and self.steps > self.max_steps:
            raise Err('Limit')
        if self.depth >= self.max_depth:
            raise Err('Limit')
        self.depth += 1
        try:
            return self.node(n)
        finally:
            self.depth -= 1

    def node(self, n):
        k = n[0]
        if k == 'lit':
            return n[1]
        if k == 'var':
            if n[1] in SCOPE:
                return SCOPE[n[1]]
            if self.strict:
                raise Err('Undefined')
            return None
        if k == 'list':
            vals = [self.ev(c) for c in n[1]]
            if len(vals) > self.max_collection:
                raise Err('Limit')
            return vals
        if k == 'map':
            out = {}
            for key, vexpr in n[1]:
                v = self.ev(vexpr)
                if key in out:
                    out[key] = v
                else:
                    out[key] = v
            return out
        if k == 'and':
            if not truthy(self.ev(n[1])):
                return False
            return truthy(self.ev(n[2]))
        if k == 'or':
            if truthy(self.ev(n[1])):
                return True
            return truthy(self.ev(n[2]))
        if k == 'ternary':
            return self.ev(n[2]) if truthy(self.ev(n[1])) else self.ev(n[3])
        if k == 'elvis':
            l = self.ev(n[1])
            return l if truthy(l) else self.ev(n[2])
        if k == 'coalesce':
            l = self.ev(n[1])
            return self.ev(n[2]) if l is None else l
        if k == 'range':
            lo, hi = self.ev(n[1]), self.ev(n[2])
            if isinstance(lo, bool) or isinstance(hi, bool) or not isinstance(lo, int) or not isinstance(hi, int):
                raise Err('Type')
            count = abs(hi - lo) + 1
            if count > self.max_collection:
                raise Err('Limit')
            step = 1 if hi >= lo else -1
            return [lo + step * i for i in range(count)]
        if k == 'unary':
            x = self.ev(n[2])
            op = n[1]
            if op in ('not', 'empty'):
                return not truthy(x)
            if op == 'size':
                return self.size_of(x)
            if op == 'neg':
                if isinstance(x, bool) or not is_number(x):
                    raise Err('Type')
                if isinstance(x, int):
                    if x == I64_MIN:
                        raise Err('Overflow')
                    return -x
                return 0.0 - x
            if op == 'pos':
                if isinstance(x, bool) or not is_number(x):
                    raise Err('Type')
                return x
        if k == 'bin':
            x = self.ev(n[2])
            y = self.ev(n[3])
            return self.binary(n[1], x, y)
        if k == 'prop':
            b = self.ev(n[1])
            if b is None:
                if n[3]:
                    return None
                if self.strict:
                    raise Err('Undefined')
                return None
            if isinstance(b, dict):
                if n[2] in b:
                    return b[n[2]]
                if self.strict:
                    raise Err('Undefined')
                return None
            if isinstance(b, Obj):
                v, found = host_get(b, n[2])
                if not found:
                    if self.strict:
                        raise Err('Undefined')
                    return None
                return v
            raise Err('Type')
        if k == 'index':
            b = self.ev(n[1])
            idx = self.ev(n[2])
            if b is None:
                if n[3]:
                    return None
                raise Err('Type')
            if isinstance(b, list):
                if isinstance(idx, bool) or not isinstance(idx, int):
                    raise Err('Type')
                if idx < 0 or idx >= len(b):
                    raise Err('Index')
                return b[idx]
            if isinstance(b, str):
                if isinstance(idx, bool) or not isinstance(idx, int):
                    raise Err('Type')
                bs = b.encode('utf-8')
                if idx < 0 or idx >= len(bs):
                    raise Err('Index')
                return bs[idx:idx + 1].decode('latin-1')
            if isinstance(b, dict):
                if not isinstance(idx, str):
                    raise Err('Type')
                if idx in b:
                    return b[idx]
                if self.strict:
                    raise Err('Undefined')
                return None
            if isinstance(b, Obj):
                if not isinstance(idx, str):
                    raise Err('Type')
                v, found = host_get(b, idx)
                if not found and self.strict:
                    raise Err('Undefined')
                return v
            raise Err('Type')
        if k == 'call':
            args = [self.ev(a) for a in n[2]]
            return self.function(n[1], args)
        if k == 'method':
            b = self.ev(n[1])
            args = [self.ev(a) for a in n[3]]
            if b is None:
                if n[4]:
                    return None
                raise Err('Type')
            if isinstance(b, Obj):
                return self.host_call(b, n[2], args)
            return self.builtin_method(b, n[2], args)
        raise Err('Type')

    def size_of(self, v):
        if isinstance(v, (str, list, dict)):
            return len(v.encode('utf-8')) if isinstance(v, str) else len(v)
        if v is None:
            return 0
        raise Err('Type')

    def binary(self, op, x, y):
        if op == 'eq':
            return equals(x, y)
        if op == 'ne':
            return not equals(x, y)
        if op in ('in', 'nin'):
            if isinstance(y, list):
                found = any(equals(i, x) for i in y)
            elif isinstance(y, dict):
                found = isinstance(x, str) and x in y
            elif isinstance(y, str):
                if not isinstance(x, str):
                    raise Err('Type')
                found = x.encode() in y.encode()
            else:
                raise Err('Type')
            return found if op == 'in' else not found
        if op in ('starts', 'ends'):
            if not isinstance(x, str) or not isinstance(y, str):
                raise Err('Type')
            return x.startswith(y) if op == 'starts' else x.endswith(y)
        if op in ('lt', 'le', 'gt', 'ge'):
            if is_number(x) and is_number(y):
                a, b = x, y
                if a != a or b != b:
                    return False
            elif isinstance(x, str) and isinstance(y, str):
                a, b = x.encode('utf-8'), y.encode('utf-8')
            else:
                raise Err('Type')
            return {'lt': a < b, 'le': a <= b, 'gt': a > b, 'ge': a >= b}[op]
        # arithmetic
        if op == 'add' and (isinstance(x, str) or isinstance(y, str)):
            l, r = text_of(x), text_of(y)
            if len(l.encode()) + len(r.encode()) > self.max_string:
                raise Err('Limit')
            return l + r
        if not is_number(x) or not is_number(y) or isinstance(x, bool) or isinstance(y, bool):
            raise Err('Type')
        if isinstance(x, int) and isinstance(y, int):
            if op == 'add':
                return check_i64(x + y)
            if op == 'sub':
                return check_i64(x - y)
            if op == 'mul':
                return check_i64(x * y)
            if op == 'div':
                if y == 0:
                    raise Err('DivideByZero')
                if x == I64_MIN and y == -1:
                    raise Err('Overflow')
                q, r = trunc_div_rem(x, y)
                if r == 0:
                    return q
                return float(x) / float(y)
            if op == 'mod':
                if y == 0:
                    raise Err('DivideByZero')
                if y == -1:
                    return 0
                return trunc_div_rem(x, y)[1]
        fx, fy = float(x), float(y)
        if op == 'add':
            return fx + fy
        if op == 'sub':
            return fx - fy
        if op == 'mul':
            return fx * fy
        if op == 'div':
            if fy == 0.0:
                raise Err('DivideByZero')
            return fx / fy
        if op == 'mod':
            if fy == 0.0:
                raise Err('DivideByZero')
            q = fx / fy
            if q > 9.0e15 or q < -9.0e15:
                raise Err('Overflow')
            return fx - float(int(q)) * fy
        raise Err('Type')

    def host_call(self, obj, name, args):
        if obj.ident == 1:
            if name == 'greet':
                if len(args) != 1:
                    raise Err('Type')
                return 'Hello, ' + text_of(args[0]) + '!'
            if name == 'add':
                if len(args) != 2:
                    raise Err('Type')
                return self.binary('add', args[0], args[1])
            if name == 'secret':
                raise Err('Denied')
        raise Err('Denied')

    def builtin_method(self, base, name, args):
        def int_arg(i):
            if i >= len(args) or isinstance(args[i], bool) or not isinstance(args[i], int):
                raise Err('Type')
            return args[i]

        def str_arg(i):
            if i >= len(args) or not isinstance(args[i], str):
                raise Err('Type')
            return args[i]
        if isinstance(base, str):
            b = base.encode('utf-8')
            if name in ('length', 'size'):
                return len(b)
            if name == 'isEmpty':
                return len(b) == 0
            if name == 'toUpperCase':
                return bytes(c - 32 if 97 <= c <= 122 else c for c in b).decode('utf-8')
            if name == 'toLowerCase':
                return bytes(c + 32 if 65 <= c <= 90 else c for c in b).decode('utf-8')
            if name == 'trim':
                return b.strip(b' \t\n\r').decode('utf-8')
            if name in ('contains', 'startsWith', 'endsWith', 'indexOf'):
                n = str_arg(0).encode('utf-8')
                if name == 'contains':
                    return n in b
                if name == 'indexOf':
                    return b.find(n)
                return b.startswith(n) if name == 'startsWith' else b.endswith(n)
            if name == 'substring':
                lo = int_arg(0)
                hi = len(b)
                if len(args) > 1:
                    hi = int_arg(1)
                if lo < 0 or hi > len(b) or lo > hi:
                    raise Err('Index')
                return b[lo:hi].decode('utf-8')
            if name == 'charAt':
                i = int_arg(0)
                if i < 0 or i >= len(b):
                    raise Err('Index')
                return b[i:i + 1].decode('latin-1')
            if name == 'concat':
                other = str_arg(0)
                if len(b) + len(other.encode()) > self.max_string:
                    raise Err('Limit')
                return base + other
            raise Err('Denied')
        if isinstance(base, list):
            if name in ('size', 'length'):
                return len(base)
            if name == 'isEmpty':
                return len(base) == 0
            if name == 'contains':
                if len(args) != 1:
                    raise Err('Type')
                return any(equals(i, args[0]) for i in base)
            if name == 'get':
                i = int_arg(0)
                if i < 0 or i >= len(base):
                    raise Err('Index')
                return base[i]
            if name == 'indexOf':
                if len(args) != 1:
                    raise Err('Type')
                for i, v in enumerate(base):
                    if equals(v, args[0]):
                        return i
                return -1
            if name == 'join':
                sep = str_arg(0)
                out = sep.join(text_of(i) for i in base)
                if len(out.encode()) > self.max_string:
                    raise Err('Limit')
                return out
            raise Err('Denied')
        if isinstance(base, dict):
            if name == 'size':
                return len(base)
            if name == 'isEmpty':
                return len(base) == 0
            if name == 'containsKey':
                return str_arg(0) in base
            if name == 'get':
                return base.get(str_arg(0))
            if name == 'keys':
                return list(base.keys())
            if name == 'values':
                return list(base.values())
            raise Err('Denied')
        raise Err('Denied')

    def function(self, name, args):
        if name == 'size':
            if len(args) != 1:
                raise Err('Type')
            return self.size_of(args[0])
        if name == 'empty':
            if len(args) != 1:
                raise Err('Type')
            return not truthy(args[0])
        if name == 'str':
            if len(args) != 1:
                raise Err('Type')
            t = text_of(args[0])
            if len(t.encode()) > self.max_string:
                raise Err('Limit')
            return t
        if name == 'int':
            if len(args) != 1:
                raise Err('Type')
            v = args[0]
            if isinstance(v, bool):
                return 1 if v else 0
            if isinstance(v, int):
                return v
            if isinstance(v, float):
                if v != v or v > 9.2e18 or v < -9.2e18:
                    raise Err('Overflow')
                return int(v)
            if isinstance(v, str):
                try:
                    r = int(v)
                except ValueError:
                    raise Err('Type')
                if not v.lstrip('+-').isdigit() or v != v.strip():
                    raise Err('Type')
                if r > I64_MAX or r < I64_MIN:
                    raise Err('Type')
                return r
            raise Err('Type')
        if name == 'float':
            if len(args) != 1:
                raise Err('Type')
            v = args[0]
            if isinstance(v, bool):
                raise Err('Type')
            if isinstance(v, (int, float)):
                return float(v)
            if isinstance(v, str):
                try:
                    return float(v)
                except ValueError:
                    raise Err('Type')
            raise Err('Type')
        if name == 'abs':
            if len(args) != 1:
                raise Err('Type')
            v = args[0]
            if isinstance(v, bool) or not is_number(v):
                raise Err('Type')
            if isinstance(v, int):
                if v == I64_MIN:
                    raise Err('Overflow')
                return abs(v)
            return abs(v)
        if name in ('min', 'max'):
            if len(args) != 2:
                raise Err('Type')
            x, y = args
            if is_number(x) and is_number(y) and not isinstance(x, bool) and not isinstance(y, bool):
                if x != x or y != y:
                    raise Err('Type')
                if name == 'min':
                    return x if x <= y else y
                return x if x >= y else y
            if isinstance(x, str) and isinstance(y, str):
                a, b = x.encode(), y.encode()
                if name == 'min':
                    return x if a <= b else y
                return x if a >= b else y
            raise Err('Type')
        if name in ('floor', 'ceil', 'round'):
            if len(args) != 1:
                raise Err('Type')
            v = args[0]
            if isinstance(v, bool) or not is_number(v):
                raise Err('Type')
            if isinstance(v, int):
                return v
            if v != v or v > 9.0e15 or v < -9.0e15:
                raise Err('Overflow')
            import math
            if name == 'floor':
                return math.floor(v)
            if name == 'ceil':
                return math.ceil(v)
            return math.floor(v + 0.5)
        # host global functions
        if name == 'double':
            if len(args) != 1:
                raise Err('Type')
            v = args[0]
            if isinstance(v, bool) or not is_number(v):
                raise Err('Type')
            return v * 2 if isinstance(v, float) else check_i64(v * 2)
        if name == 'upper':
            if len(args) != 1 or not isinstance(args[0], str):
                raise Err('Type')
            return bytes(c - 32 if 97 <= c <= 122 else c for c in args[0].encode()).decode('utf-8')
        if name == 'secret':
            raise Err('Denied')
        raise Err('Denied')


def serialize(v):
    if v is None:
        return 'N'
    if isinstance(v, bool):
        return 'T' if v else 'F'
    if isinstance(v, int):
        return 'i%d' % v
    if isinstance(v, float):
        return 'f%016x' % struct.unpack('>Q', struct.pack('>d', v))[0]
    if isinstance(v, str):
        return 's' + (v.encode('utf-8').hex() or '-')
    if isinstance(v, list):
        return '[' + ','.join(serialize(i) for i in v) + ']'
    if isinstance(v, dict):
        return '{' + ','.join((k.encode('utf-8').hex() or '-') + ':' + serialize(i) for k, i in v.items()) + '}'
    return 'o%d' % v.ident


def evaluate(src, strict=False, max_steps=100000, max_depth=64):
    limits = {'max_string': 65536}
    try:
        toks = lex(src, limits)
        p = Parser(toks, max_depth)
        tree = p.expr()
        if p.t[p.i]['kind'] != 'end':
            raise Err('Syntax')
        it = Interp(strict, max_steps, max_depth)
        return 'V ' + serialize(it.ev(tree))
    except Err as e:
        return 'E ' + e.name


# ---- vectors ----
HAND = [
    # literals
    '1', '-1', '+3', '1.5', '.5', '1e3', '2.5e-1', '10L', "'hi'", '"hi"', "'a\\nb'", "'it\\'s'", "'\\u0041'", 'true', 'false', 'null',
    '[]', '[1, 2, 3]', "[1, 'a', true, null, [2]]", '{}', "{'a': 1, b: 2}", "{'k': [1, {'z': 2}]}", '1..5', '5..1', '3..3',
    # arithmetic and promotion
    '1 + 2', '7 - 10', '6 * 7', '8 / 2', '7 / 2', '-7 / 2', '7 % 3', '-7 % 3', '7 % -3', '7.5 % 2', '2.5 * 2', '1 + 2.5', 'x / y', 'x div y', 'x mod y',
    '7 / 0', '7 % 0', '7.0 / 0', '7.0 % 0.0', 'big + 1', 'big * 2', 'neg - big - big', '-big - 2', 'abs(neg)', 'abs(-2.5)', '-(-9223372036854775807 - 1)',
    '2 + 3 * 4', '(2 + 3) * 4', '10 - 2 - 3', '2 * 3 % 4', '1 - -1', '- - 2', '-x', '+f', '-f',
    # strings
    "'a' + 'b'", "'a' + 1", "1 + 'a'", "'x' + null", "'x' + true", "'x' + 2.5", "'x' + 3.0", "'x' + [1, 2]", "'x' + {'a': 1}", "'x' + user", '"a" < "b"', "'b' > 'a'", "'abc' < 'abd'", "'' < 'a'",
    "s.length()", "s.size()", "s.toUpperCase()", "'MiXed'.toLowerCase()", "'  pad  '.trim()", "s.contains('ell')", "s.startsWith('he')", "s.endsWith('lo')", "s.indexOf('l')",
    "s.substring(1)", "s.substring(1, 3)", "s.substring(3, 1)", "s.substring(0, 99)", "s.charAt(1)", "s.charAt(9)", "s.concat('!')", "s.isEmpty()", "e.isEmpty()", "s[0]", "s[4]", "s[5]", "s[-1]",
    # comparison and equality
    '1 == 1', '1 == 1.0', '1 != 2', "'a' == 'a'", "'a' == 1", 'null == null', 'null == 0', 'true == true', 'true == 1', '[1, 2] == [1, 2]', '[1, 2] == [2, 1]',
    "{'a': 1, 'b': 2} == {'b': 2, 'a': 1}", '1 < 2', '2 <= 2', '3 > 2.5', '2 >= 3', '1 lt 2', '1 le 1', '2 gt 1', '2 ge 3', '1 eq 1', '1 ne 1', "1 < 'a'", 'null < 1', 'true < false',
    # logic
    'true && false', 'true || false', '!true', 'not false', 'true and true', 'false or false', '1 && 2', '0 || 0', "'' || 'x'", "null || 0", '!0', '!!5', 'e || s', 'items && s',
    '(1 / 0) || true', 'false && (1 / 0)', 'true || (1 / 0)', 'true && (1 / 0)',
    # ternary, elvis, coalesce
    'true ? 1 : 2', 'false ? 1 : 2', '0 ? 1 : 2', "'' ? 1 : 2", 'x > 5 ? "big" : "small"', 'true ? false ? 1 : 2 : 3', 'false ? 1 : true ? 2 : 3',
    "e ?: 'dflt'", "s ?: 'dflt'", 'null ?: 5', '0 ?: 5', 'n ?? 4', '0 ?? 4', "e ?? 'z'", 'missing ?? 9',
    # membership and prefix operators
    '2 =~ items', '9 =~ items', '9 !~ items', "'a' =~ m", "'q' =~ m", "'ell' =~ s", "'xyz' !~ s", "s =^ 'he'", "s =$ 'lo'", "s =^ 'lo'", '1 =~ 1', '1 =^ 2',
    # empty and size
    'empty e', 'empty s', 'empty items', 'empty []', 'empty n', 'empty 0', 'empty(items)', 'size items', 'size(s)', 'size m', 'size(null)', 'size 5', 'size(items) + 1', 'empty items == false',
    # collections and navigation
    'items[0]', 'items[2]', 'items[3]', 'items[-1]', "items[1.5]", "items['a']", "m['a']", "m['b']['c']", 'm.a', 'm.b.c', 'm.q', "m['q']", 'm.b.q', 'n.x', 'n?.x', 'n?.x.y', 'n[0]', 'n?[0]',
    'items.size()', 'items.isEmpty()', 'items.contains(2)', 'items.contains(9)', 'items.get(1)', 'items.get(7)', 'items.indexOf(3)', 'items.indexOf(9)', "words.join('-')", "items.join(', ')",
    'm.size()', "m.containsKey('a')", "m.containsKey('x')", "m.get('a')", "m.get('x')", 'm.keys()', 'm.values()', 'm.isEmpty()', "{}.isEmpty()", "[1, 2].size()", "{'a': 1}.keys()",
    # objects: properties, methods, sandbox
    'user', 'user.name', 'user.age', 'user.age + 1', 'user.active && true', 'user.score * 2', 'user.tags', 'user.tags[1]', 'user.tags.size()', 'user.address.city', 'user.address.lines[0]', "user['name']", 'user.manager', 'user.manager.name',
    'user.manager?.name', 'user.nothing', "user.greet('Bob')", 'user.greet(user.name)', 'user.add(1, 2)', "user.add('a', 'b')", 'user.secret()', 'user.undefined()', 'user.greet()', 'user == user', 'user.address == user.address', 'user == user.address',
    'double(21)', 'double(1.25)', "upper('abc')", 'secret()', 'nosuch()', "double('a')", 'size(user.tags)', 'str(1.5)', 'str(user)', 'str(null)', 'str([1, 2.0, "a"])', 'int(2.9)', 'int(-2.9)', "int('42')", "int('x')", 'int(true)',
    'float(3)', "float('2.5')", 'float(true)', 'min(3, 4)', 'max(3, 4.5)', "min('b', 'a')", "max('b', 'a')", 'min(1, "a")', 'floor(2.7)', 'ceil(2.1)', 'round(2.5)', 'round(-2.5)', 'round(2.4)', 'floor(-0.5)', 'ceil(-0.5)', 'abs(2)', 'abs("x")',
    # syntax errors
    '', ' ', '1 +', '+', '(1', '1)', '[1, 2', '{a: }', "{'a' 1}", '1 2', 'a b', "'unterminated", '1 ? 2', '1 ? 2 3', 'x.', 'x.1', '*', '1 ** 2', '#', '@x', "'\\u12'", 'items[', 'f(', 'f(1,', 'f(,)',
    # undefined (non-strict null) and precedence
    'missing', 'missing.x', 'missing + 1', 'missing == null', '1 + 2 * 3 - 4 / 2', 'true || false && false', '(true || false) && false', '1 < 2 == true', '!false == true', '- x * 2', 'empty n || size items > 2',
    "'a' + 'b' == 'ab'", '1 + 2 == 3 && 4 > 3', 'x > 5 && y < 5 ? x : y', 'items[0] + items[1] * items[2]',
]

lines = []


def add(src, strict=False, max_steps=100000, max_depth=64):
    res = evaluate(src, strict, max_steps, max_depth)
    lines.append('X %d %d %d %s => %s' % (1 if strict else 0, max_steps, max_depth, src.encode('utf-8').hex() or '-', res))


for h in HAND:
    add(h)
for h in HAND[:90]:
    add(h, strict=True)
# step and depth limits
add('1 + 2 + 3 + 4 + 5', max_steps=3)
add('1 + 2 + 3 + 4 + 5', max_steps=9)
add('1 + 2 + 3 + 4 + 5', max_steps=10)
add('items.size() + m.size()', max_steps=4)
add('[1, 2, 3, 4, 5, 6, 7, 8]', max_steps=8)
add('[1, 2, 3, 4, 5, 6, 7, 8]', max_steps=9)
add('1..10000')
add('1..10001')
add('((((((((((1))))))))))', max_depth=5)
add('((((((((((1))))))))))', max_depth=12)
add('-----------------1', max_depth=10)
add('[[[[[[1]]]]]]', max_depth=4)
add('[[[[[[1]]]]]]', max_depth=8)

# random trees
VARS = ['x', 'y', 'f', 's', 't', 'n', 'items', 'm', 'user', 'words', 'neg', 'z', 'half', 'e']
BIN = ['+', '-', '*', '/', '%', '==', '!=', '<', '<=', '>', '>=', '&&', '||', '=~', '!~', '..', '??', '?:', 'div', 'mod', 'and', 'or', 'eq', 'ne', 'lt', 'gt']


def rand_leaf():
    r = random.random()
    if r < 0.3:
        return random.choice(['0', '1', '2', '3', '7', '10', '-4', '100'])
    if r < 0.4:
        return random.choice(['0.5', '1.5', '2.25', '3.0', '-0.5'])
    if r < 0.5:
        return random.choice(["'a'", "'ab'", "''", "'xyz'"])
    if r < 0.55:
        return random.choice(['true', 'false', 'null'])
    return random.choice(VARS)


def rand_expr(depth):
    if depth <= 0 or random.random() < 0.15:
        return rand_leaf()
    r = random.random()
    if r < 0.5:
        op = random.choice(BIN)
        return '(%s %s %s)' % (rand_expr(depth - 1), op, rand_expr(depth - 1))
    if r < 0.6:
        return '(%s ? %s : %s)' % (rand_expr(depth - 1), rand_expr(depth - 1), rand_expr(depth - 1))
    if r < 0.7:
        return random.choice(['!', '-', 'not ', 'empty ', 'size ']) + '(' + rand_expr(depth - 1) + ')'
    if r < 0.78:
        return '[' + ', '.join(rand_expr(depth - 1) for _ in range(random.randint(0, 3))) + ']'
    if r < 0.84:
        return "{'k': %s, z: %s}" % (rand_expr(depth - 1), rand_expr(depth - 1))
    if r < 0.9:
        return '(%s)[%s]' % (rand_expr(depth - 1), random.choice(['0', '1', "'k'", '-1', "'name'"]))
    if r < 0.95:
        return '(%s).%s' % (rand_expr(depth - 1), random.choice(['size()', 'isEmpty()', 'name', 'k', 'toUpperCase()', 'length()']))
    return '%s(%s)' % (random.choice(['size', 'empty', 'str', 'int', 'abs', 'double', 'float', 'floor']), rand_expr(depth - 1))


for _ in range(700):
    src = rand_expr(random.randint(1, 4))
    add(src, strict=random.random() < 0.2)

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

// ---- the host world ----

fn str_value(s: str) -> expr.Value { ret expr.Value { Str: s } }

fn world_get(ctx: *void, a: *mem.Arena, handle: u32, name: str) -> (expr.Value, bool) {
    var none: expr.Value = .Null
    if handle == 1u32 {
        if text_is(name, "name") { ret (str_value("Ann"), true) }
        if text_is(name, "age") { ret (expr.Value { Int: 30i64 }, true) }
        if text_is(name, "active") { ret (expr.Value { Bool: true }, true) }
        if text_is(name, "score") { ret (expr.Value { Float: 2.5f64 }, true) }
        if text_is(name, "tags") {
            let (items, e) = mem.alloc[expr.Value](a, 2usize)
            if e != ok { ret (none, false) }
            items[0usize] = str_value("a")
            items[1usize] = str_value("b")
            ret (expr.Value { List: items[0usize..2usize] }, true)
        }
        if text_is(name, "address") { ret (expr.Value { Object: 2u32 }, true) }
        if text_is(name, "manager") { ret (none, true) }
        ret (none, false)
    }
    if handle == 2u32 {
        if text_is(name, "city") { ret (str_value("Paris"), true) }
        if text_is(name, "zip") { ret (str_value("75001"), true) }
        if text_is(name, "lines") {
            let (items, e) = mem.alloc[expr.Value](a, 2usize)
            if e != ok { ret (none, false) }
            items[0usize] = str_value("x")
            items[1usize] = str_value("y")
            ret (expr.Value { List: items[0usize..2usize] }, true)
        }
    }
    ret (none, false)
}

fn world_call(ctx: *void, a: *mem.Arena, handle: u32, name: str, args: []const expr.Value) -> (expr.Value, err) {
    var none: expr.Value = .Null
    if handle != 1u32 { ret (none, expr.Denied) }
    if text_is(name, "greet") {
        if args.len != 1usize { ret (none, expr.Type) }
        let (t, e) = expr.text_of(a, args[0usize], 65536usize)
        if e != ok { ret (none, e) }
        let (buf, alloc_error) = mem.alloc[u8](a, t.len + 8usize)
        if alloc_error != ok { ret (none, alloc_error) }
        let prefix = "Hello, "
        var n = 0usize
        while n < prefix.len {
            buf[n] = prefix[n]
            n += 1usize
        }
        var k = 0usize
        while k < t.len {
            buf[n + k] = t[k]
            k += 1usize
        }
        n += t.len
        buf[n] = 33u8
        ret (expr.Value { Str: buf[0usize..n + 1usize] }, ok)
    }
    if text_is(name, "add") {
        if args.len != 2usize { ret (none, expr.Type) }
        // the host reuses the language's own addition by evaluating the source `a + b` over bindings
        var scope: [2]expr.Binding = zero
        scope[0usize] = expr.Binding { name: "a", value: args[0usize] }
        scope[1usize] = expr.Binding { name: "b", value: args[1usize] }
        let host = world_host()
        let (v, e) = expr.evaluate(a, "a + b", scope[0usize..2usize], host, expr.default_limits())
        ret (v, e)
    }
    ret (none, expr.Denied)
}

fn world_function(ctx: *void, a: *mem.Arena, name: str, args: []const expr.Value) -> (expr.Value, err) {
    var none: expr.Value = .Null
    if text_is(name, "double") {
        if args.len != 1usize { ret (none, expr.Type) }
        switch args[0usize] {
        case .Int as i:
            if i > 4611686018427387903i64 || i < -4611686018427387904i64 { ret (none, expr.Overflow) }
            ret (expr.Value { Int: i * 2i64 }, ok)
        case .Float as f:
            ret (expr.Value { Float: f * 2.0f64 }, ok)
        default:
            ret (none, expr.Type)
        }
    }
    if text_is(name, "upper") {
        if args.len != 1usize { ret (none, expr.Type) }
        switch args[0usize] {
        case .Str as s:
            let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
            if e != ok { ret (none, e) }
            var i = 0usize
            while i < s.len {
                var c = s[i]
                if c >= 97u8 && c <= 122u8 { c -= 32u8 }
                buf[i] = c
                i += 1usize
            }
            ret (expr.Value { Str: buf[0usize..s.len] }, ok)
        default:
            ret (none, expr.Type)
        }
    }
    ret (none, expr.Denied)
}

fn world_host() -> expr.Host {
    var h: expr.Host = zero
    h.get = world_get
    h.call = world_call
    h.function = world_function
    ret h
}

fn world_scope(a: *mem.Arena, out: []expr.Binding) -> usize {
    var n = 0usize
    out[n] = expr.Binding { name: "x", value: expr.Value { Int: 7i64 } }
    n += 1usize
    out[n] = expr.Binding { name: "y", value: expr.Value { Int: 2i64 } }
    n += 1usize
    out[n] = expr.Binding { name: "f", value: expr.Value { Float: 2.5f64 } }
    n += 1usize
    out[n] = expr.Binding { name: "s", value: str_value("hello") }
    n += 1usize
    out[n] = expr.Binding { name: "e", value: str_value("") }
    n += 1usize
    out[n] = expr.Binding { name: "t", value: expr.Value { Bool: true } }
    n += 1usize
    var none: expr.Value = .Null
    out[n] = expr.Binding { name: "n", value: none }
    n += 1usize
    let (items, ie) = mem.alloc[expr.Value](a, 3usize)
    items[0usize] = expr.Value { Int: 1i64 }
    items[1usize] = expr.Value { Int: 2i64 }
    items[2usize] = expr.Value { Int: 3i64 }
    out[n] = expr.Binding { name: "items", value: expr.Value { List: items[0usize..3usize] } }
    n += 1usize
    let (inner, inner_error) = mem.alloc[expr.Pair](a, 1usize)
    inner[0usize] = expr.Pair { key: "c", value: expr.Value { Int: 2i64 } }
    let (outer, outer_error) = mem.alloc[expr.Pair](a, 2usize)
    outer[0usize] = expr.Pair { key: "a", value: expr.Value { Int: 1i64 } }
    outer[1usize] = expr.Pair { key: "b", value: expr.Value { Map: inner[0usize..1usize] } }
    out[n] = expr.Binding { name: "m", value: expr.Value { Map: outer[0usize..2usize] } }
    n += 1usize
    out[n] = expr.Binding { name: "user", value: expr.Value { Object: 1u32 } }
    n += 1usize
    let (words, we) = mem.alloc[expr.Value](a, 2usize)
    words[0usize] = str_value("foo")
    words[1usize] = str_value("bar")
    out[n] = expr.Binding { name: "words", value: expr.Value { List: words[0usize..2usize] } }
    n += 1usize
    out[n] = expr.Binding { name: "big", value: expr.Value { Int: 9223372036854775807i64 } }
    n += 1usize
    out[n] = expr.Binding { name: "neg", value: expr.Value { Int: -5i64 } }
    n += 1usize
    out[n] = expr.Binding { name: "z", value: expr.Value { Int: 0i64 } }
    n += 1usize
    out[n] = expr.Binding { name: "half", value: expr.Value { Float: 0.5f64 } }
    n += 1usize
    ret n
}

// ---- serialization to the vector's result form ----

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 87u8 + v
}

fn put(b: *str.Builder, s: str) {
    let e = str.push(b, s)
}

fn put_hex(b: *str.Builder, s: str) {
    if s.len == 0usize {
        put(b, "-")
        ret
    }
    var i = 0usize
    while i < s.len {
        let e1 = str.push_byte(b, hex_digit(s[i] / 16u8))
        let e2 = str.push_byte(b, hex_digit(s[i] % 16u8))
        i += 1usize
    }
}

fn serialize(b: *str.Builder, v: expr.Value) {
    switch v {
    case .Null:
        put(b, "N")
    case .Bool as x:
        if x {
            put(b, "T")
        } else {
            put(b, "F")
        }
    case .Int as i:
        put(b, "i")
        let e = str.push_i64(b, i)
    case .Float as f:
        put(b, "f")
        let bits = mem.bitcast[u64](f)
        var shift = 60u64
        while true {
            let nib = u8((bits >> shift) & 15u64)
            let e = str.push_byte(b, hex_digit(nib))
            if shift == 0u64 { break }
            shift -= 4u64
        }
    case .Str as s:
        put(b, "s")
        put_hex(b, s)
    case .List as l:
        put(b, "[")
        var i = 0usize
        while i < l.len {
            if i > 0usize { put(b, ",") }
            serialize(b, l[i])
            i += 1usize
        }
        put(b, "]")
    case .Map as m:
        put(b, "{")
        var i = 0usize
        while i < m.len {
            if i > 0usize { put(b, ",") }
            put_hex(b, m[i].key)
            put(b, ":")
            serialize(b, m[i].value)
            i += 1usize
        }
        put(b, "}")
    case .Object as o:
        put(b, "o")
        let e = str.push_u32(b, o)
    default:
        put(b, "?")
    }
}

fn error_name(e: err) -> str {
    if e == expr.Syntax { ret "Syntax" }
    if e == expr.Type { ret "Type" }
    if e == expr.DivideByZero { ret "DivideByZero" }
    if e == expr.Index { ret "Index" }
    if e == expr.Undefined { ret "Undefined" }
    if e == expr.Limit { ret "Limit" }
    if e == expr.Denied { ret "Denied" }
    if e == expr.Overflow { ret "Overflow" }
    ret "Other"
}

fn check_line(line: str) -> u8 {
    var arena_buf: [1048576]u8 = zero
    var a = mem.arena_from(arena_buf[0usize..1048576usize])
    var src_buf: [2048]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let (strict, p1) = tok(line, p0)
    let (steps, p2) = tok(line, p1)
    let (depth, p3) = tok(line, p2)
    let (src_hex, p4) = tok(line, p3)
    let (arrow, p5) = tok(line, p4)
    let (verdict, p6) = tok(line, p5)
    let (result, p7) = tok(line, p6)
    let n = unhex(src_hex, src_buf[0usize..2048usize])
    var scope: [16]expr.Binding = zero
    let count = world_scope(&a, scope[0usize..16usize])
    var limits = expr.default_limits()
    limits.strict = strict[0usize] == 49u8
    limits.max_steps = u32(dec(steps))
    limits.max_depth = u32(dec(depth))
    let (v, e) = expr.evaluate(&a, src_buf[0usize..n], scope[0usize..count], world_host(), limits)
    if verdict[0usize] == 69u8 {
        if e == ok { ret 1u8 }
        if !text_is(error_name(e), result) { ret 2u8 }
        ret 0u8
    }
    if e != ok { ret 3u8 }
    let (b0, be) = str.builder(&a, 256usize)
    if be != ok { ret 4u8 }
    var b = b0
    serialize(&b, v)
    let got_text = str.done(&b)
    if !text_is(got_text, result) {
        let shown = io.print(got_text)
        ret 5u8
    }
    ret 0u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // compile once, run against two scopes
    var limits = expr.default_limits()
    let (prog, compile_error) = expr.compile(a, "x * 2 + y", limits)
    if compile_error != ok { os.exit(101i32) }
    var scope: [2]expr.Binding = zero
    scope[0usize] = expr.Binding { name: "x", value: expr.Value { Int: 3i64 } }
    scope[1usize] = expr.Binding { name: "y", value: expr.Value { Int: 4i64 } }
    let (v1, e1) = expr.run(a, &prog, scope[0usize..2usize], world_host(), limits)
    if e1 != ok { os.exit(102i32) }
    switch v1 {
    case .Int as i:
        if i != 10i64 { os.exit(103i32) }
    default:
        os.exit(104i32)
    }
    scope[0usize] = expr.Binding { name: "x", value: expr.Value { Int: 10i64 } }
    let (v2, e2) = expr.run(a, &prog, scope[0usize..2usize], world_host(), limits)
    if e2 != ok { os.exit(105i32) }
    switch v2 {
    case .Int as i:
        if i != 24i64 { os.exit(106i32) }
    default:
        os.exit(107i32)
    }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("algo expr ok")
    ret ok
}
'''

src = ('// e.algo.expr against an independent Python implementation of the documented language (own tokenizer,\n'
       '// parser and evaluator, same host world): hand-written expressions for every operator, literal, built-in\n'
       '// and refusal, step and depth limits replicated exactly, and 700 random trees (D2804). X lines carry\n'
       '// strict flag, step and depth limits, the expression in hex and `V <result>` or `E <Name>`. Generated by\n'
       '// scripts/gen_expr_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.str\nuse e.algo.expr\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors,', sum(1 for l in lines if '=> V' in l), 'values,', sum(1 for l in lines if '=> E' in l), 'errors')
