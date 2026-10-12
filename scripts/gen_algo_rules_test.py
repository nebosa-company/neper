"""Expected values for tests/selfhost/fixtures/link/algo_rules (L161, D2760).

An independent model of the engine's documented semantics: no network at all. Every cycle it
enumerates every match from scratch over the live facts, drops the ones already fired (a fired
match that stops matching is forgotten), and fires the best by (salience, recency, specificity,
rule order). Decision tables are evaluated straight from their rows, not through rules.
Run it to print the vectors the fixture embeds.
"""
import re

ANY, EQ, NE, LT, LE, GT, GE = range(7)
OPS = {'==': EQ, '!=': NE, '<=': LE, '>=': GE, '<': LT, '>': GT}


def cmp(op, x, y):
    return {ANY: True, EQ: x == y, NE: x != y, LT: x < y, LE: x <= y, GT: x > y, GE: x >= y}[op]


class Model:
    def __init__(self):
        self.facts = []      # (kind, tuple6, alive)
        self.rules = []
        self.syms = {}
        self.fired = set()
        self.log = []

    def sym(self, name):
        return self.syms.setdefault(name, len(self.syms))

    def const(self, tok):
        return self.sym(tok[1:]) if tok.startswith(':') else int(tok)

    def load(self, src):
        src = re.sub(r'//[^\n]*', '', src)
        for m in re.finditer(r'rule\s+(\w+)(?:\s+salience\s+(-?\d+))?\s+when(.*?)\bthen\b(.*?)\bend\b', src, re.S):
            name, sal, when, then = m.group(1), int(m.group(2) or 0), m.group(3), m.group(4)
            conds = []
            for cm in re.finditer(r'(not\s+)?(\w+)\s*\(([^)]*)\)', when):
                terms = []
                for a in [x.strip() for x in cm.group(3).split(',') if x.strip()]:
                    terms.append(self.term(a))
                conds.append((bool(cm.group(1)), cm.group(2), terms))
            acts = []
            for am in re.finditer(r'assert\s+(\w+)\s*\(([^)]*)\)|retract\s+(\d+)|\bhalt\b', then):
                if am.group(1):
                    args = [self.aterm(x.strip()) for x in am.group(2).split(',') if x.strip()]
                    acts.append(('assert', am.group(1), args))
                elif am.group(3):
                    acts.append(('retract', int(am.group(3))))
                else:
                    acts.append(('halt',))
            self.rules.append(dict(name=name, sal=sal, conds=conds, acts=acts))

    def term(self, a):
        if a == '_':
            return (None, ANY, None, None)
        m = re.match(r'^(?:\?(\w+))?\s*(==|!=|<=|>=|<|>)?\s*(\?\w+|:\w+|-?\d+)?$', a)
        bind, op, operand = m.group(1), m.group(2), m.group(3)
        if op:
            if operand.startswith('?'):
                return (bind, OPS[op], None, operand[1:])
            return (bind, OPS[op], self.const(operand), None)
        if bind:
            return (bind, ANY, None, None)
        return (None, EQ, self.const(operand), None)

    def aterm(self, a):
        m = re.match(r'^\?(\w+)\s*(?:\+\s*(\?\w+|-?\d+)|(-\d+))?$', a)
        if m:
            if m.group(2) and m.group(2).startswith('?'):
                return ('addv', m.group(1), m.group(2)[1:])
            if m.group(2) or m.group(3):
                return ('addc', m.group(1), int(m.group(2) or m.group(3)))
            return ('var', m.group(1))
        return ('const', self.const(a))

    def assert_(self, kind, *args):
        t = tuple(args) + (0,) * (6 - len(args))
        for i, (k, f, alive) in enumerate(self.facts):
            if alive and k == kind and f == t:
                return i
        self.facts.append((kind, t, True))
        return len(self.facts) - 1

    def retract(self, kind, *args):
        t = tuple(args) + (0,) * (6 - len(args))
        for i, (k, f, alive) in enumerate(self.facts):
            if alive and k == kind and f == t:
                self.facts[i] = (k, f, False)
                return

    def match_one(self, cond, fact, env):
        _, kind, terms = cond
        k, f, alive = fact
        if not alive or k != kind:
            return None
        env = dict(env)
        for j, (bind, op, v, rv) in enumerate(terms):
            val = f[j]
            if op != ANY:
                rhs = env[rv] if rv is not None else v
                if not cmp(op, val, rhs):
                    return None
            if bind is not None:
                if bind in env and env[bind] != val:
                    return None
                env[bind] = val
        return env

    def matches(self):
        out = []
        for ri, r in enumerate(self.rules):
            def go(ci, env, ids):
                if ci == len(r['conds']):
                    out.append((ri, tuple(ids), env))
                    return
                cond = r['conds'][ci]
                if cond[0]:
                    for fact in self.facts:
                        if self.match_one(cond, fact, env) is not None:
                            return
                    go(ci + 1, env, ids + [None])
                    return
                for fi, fact in enumerate(self.facts):
                    e2 = self.match_one(cond, fact, env)
                    if e2 is not None:
                        go(ci + 1, e2, ids + [fi])
            go(0, {}, [])
        return out

    def spec(self, r):
        n = 0
        for neg, kind, terms in r['conds']:
            for bind, op, v, rv in terms:
                n += (bind is not None) + (op != ANY)
        return n

    def fire(self, limit=1000):
        n = 0
        while n < limit:
            ms = self.matches()
            self.fired &= {(ri, ids) for ri, ids, _ in ms}
            cands = [m for m in ms if (m[0], m[1]) not in self.fired]
            if not cands:
                break
            best = max(cands, key=lambda m: (self.rules[m[0]]['sal'],
                                             sorted([i for i in m[1] if i is not None], reverse=True),
                                             self.spec(self.rules[m[0]]), -m[0]))
            ri, ids, env = best
            self.fired.add((ri, ids))
            self.log.append(self.rules[ri]['name'])
            n += 1
            halted = False
            for act in self.rules[ri]['acts']:
                if act[0] == 'assert':
                    vals = []
                    for t in act[2]:
                        if t[0] == 'const':
                            vals.append(t[1])
                        elif t[0] == 'var':
                            vals.append(env[t[1]])
                        elif t[0] == 'addv':
                            vals.append(env[t[1]] + env[t[2]])
                        else:
                            vals.append(env[t[1]] + t[2])
                    self.assert_(act[1], *vals)
                elif act[0] == 'retract':
                    fi = ids[act[1]]
                    k, f, alive = self.facts[fi]
                    self.facts[fi] = (k, f, False)
                else:
                    halted = True
            if halted:
                break
        return n

    def live(self, kind):
        return sorted(f[:] for k, f, a in self.facts if a and k == kind)


def table_first(rows, row_in):
    return table_all(rows, row_in)[:1]


def table_all(rows, row_in):
    return [out for cells, out in rows
            if all(c is None or cmp(op, row_in[field], c) for (field, op), c in zip(COLS, cells))]


# columns: (field, op) over order(age, weight, premium_class)
COLS = [(0, GE), (0, LT), (1, GE)]
ROWS = [([65, None, None], 30), ([18, 65, 100], 10), ([18, 65, None], 5), ([None, 18, None], 0)]
# the fixture's rows use the same cells: None is ANY


def main():
    s = Model()
    for a, b in [('ann', 'bob'), ('bob', 'cy'), ('cy', 'di'), ('bob', 'eve')]:
        s.assert_('parent', s.sym(a), s.sym(b))
    s.load('rule grand when parent(?x, ?y) parent(?y, ?z) then assert grandparent(?x, ?z) end')
    n = s.fire()
    print('S1 fired', n, 'grandparent', len(s.live('grandparent')), 'log', s.log)
    print('S1 ann-cy', (s.sym('ann'), s.sym('cy'), 0, 0, 0, 0) in s.live('grandparent'))

    c = Model()
    c.load('''rule base when parent(?x, ?y) then assert anc(?x, ?y) end
              rule step when anc(?x, ?y) parent(?y, ?z) then assert anc(?x, ?z) end''')
    for a, b in [(1, 2), (2, 3), (3, 4), (2, 5), (5, 6)]:
        c.assert_('parent', a, b)
    n = c.fire()
    print('S2 fired', n, 'anc', len(c.live('anc')), 'log', ''.join('b' if x == 'base' else 's' for x in c.log))

    p = Model()
    p.load('''rule low when a(?x) then assert lo(?x) end
              rule high salience 10 when a(?x) then assert hi(?x) end
              rule wide salience 10 when a(?x>1) then assert wi(?x) end
              rule pair when a(?x) a(?y>?x) then assert pr(?x, ?y) end''')
    for v in (1, 2, 3):
        p.assert_('a', v)
    n = p.fire()
    print('S3 fired', n, 'log', p.log)

    f = Model()
    f.load('rule step when state(?n<10, ?a, ?b) then retract 0 assert state(?n+1, ?b, ?a+?b) end')
    f.assert_('state', 0, 0, 1)
    n = f.fire()
    print('S4 fired', n, 'state', f.live('state'))

    g = Model()
    g.load('rule childless when person(?x) not has_child(?x) then assert childless(?x) end')
    g.assert_('person', 1)
    g.assert_('person', 2)
    g.assert_('has_child', 1)
    n1 = g.fire()
    print('S5a fired', n1, 'childless', g.live('childless'))
    g.retract('has_child', 1)
    n2 = g.fire()
    print('S5b fired', n2, 'childless', g.live('childless'))
    g.assert_('person', 3)
    g.assert_('has_child', 3)
    n3 = g.fire()
    print('S5c fired', n3, 'childless', g.live('childless'))

    h = Model()
    h.load('''rule inc when n(?x<5) then retract 0 assert n(?x+1) end
              rule stop salience 10 when n(3) then halt end''')
    h.assert_('n', 0)
    n = h.fire()
    print('S6 fired', n, 'n', h.live('n'), 'log', h.log)

    print('S7 tables')
    for age, wt in [(70, 0), (30, 120), (30, 50), (20, 99), (10, 0), (65, 0), (18, 100), (18, 99)]:
        inp = (age, wt)
        print(' in', inp, 'first', table_first(ROWS, inp), 'all', table_all(ROWS, inp))


if __name__ == '__main__':
    main()
