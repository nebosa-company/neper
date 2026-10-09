"""Reference and fixture generator for e.algo.predicate (L025).

  python scripts/predicate_reference.py

A transcription of petcow's Spartan filter engine (src/spartan/filter.rs, predicate.rs) onto plain Python
dictionaries and lists: parse (named refusals in the Rust order) and eval for every operator and the three built-in
predicates, with its own tests as the first cases and then seeded random filters over seeded random attribute bags.
Regex patterns are limited to the common subset both Python's `re` and Neper's engine run the same way. Writes
tests/selfhost/fixtures/link/algo_predicate/src/main.e from scripts/predicate_fixture_template.e.
"""
import json
import pathlib
import random
import re

OPS = {'eq': 'Eq', '==': 'Eq', 'equals': 'Eq', 'ne': 'Ne', '!=': 'Ne', 'not_equals': 'Ne', 'gt': 'Gt', '>': 'Gt', 'lt': 'Lt', '<': 'Lt',
       'ge': 'Ge', '>=': 'Ge', 'gte': 'Ge', 'le': 'Le', '<=': 'Le', 'lte': 'Le', 'in': 'In', 'not_in': 'NotIn', 'notin': 'NotIn',
       'contains': 'Contains', 'regex': 'Regex', 'matches': 'Regex', 'glob': 'Glob', 'present': 'Present', 'exists': 'Present',
       'absent': 'Absent', 'missing': 'Absent', 'any': 'Any', 'all': 'All', 'count': 'Count'}
COMPARISONS = {'Eq', 'Ne', 'Gt', 'Lt', 'Ge', 'Le'}


class Refusal(Exception):
    pass


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def parse_op(s):
    key = s.strip(' \t\n\r\x0b\x0c').lower().replace('-', '_')
    if key not in OPS:
        raise Refusal('BadOp')
    return OPS[key]


def parse(v):
    if not isinstance(v, dict):
        raise Refusal('NotMapping')
    if isinstance(v.get('builtin'), str):
        return {'kind': 'Builtin', 'name': v['builtin'], 'args': v.get('args')}
    if 'and' in v or 'or' in v or 'not' in v:
        if len(v) != 1:
            raise Refusal('BoolNotAlone')
        if 'and' in v or 'or' in v:
            kind, items = ('And', v['and']) if 'and' in v else ('Or', v['or'])
            if not isinstance(items, list):
                raise Refusal('NotList')
            return {'kind': kind, 'children': [parse(x) for x in items]}
        return {'kind': 'Not', 'children': [parse(v['not'])]}
    if not isinstance(v.get('key'), str):
        raise Refusal('MissingKey')
    has_value = 'value' in v
    value = v.get('value')
    if isinstance(v.get('op'), str):
        op = parse_op(v['op'])
    elif has_value:
        op = 'Eq'
    else:
        raise Refusal('MissingOp')
    if op not in ('Present', 'Absent', 'Any', 'All') and not has_value:
        raise Refusal('MissingValue')
    element = parse(v['element']) if 'element' in v else None
    if op in ('Any', 'All') and element is None:
        raise Refusal('MissingElement')
    count_op = None
    if op == 'Count':
        if not is_number(value):
            raise Refusal('CountNeedsNumber')
        if isinstance(v.get('count_op'), str):
            count_op = parse_op(v['count_op'])
            if count_op not in COMPARISONS:
                raise Refusal('BadCountOp')
    return {'kind': 'Leaf', 'key': v['key'], 'op': op, 'value': value, 'has_value': has_value, 'element': element, 'count_op': count_op}


def navigate(path, attrs):
    if path == '':
        return attrs.get('', _MISSING)
    parts = path.split('.')
    cur = attrs.get(parts[0], _MISSING)
    if cur is _MISSING:
        return _MISSING
    for p in parts[1:]:
        if not isinstance(cur, dict) or p not in cur:
            return _MISSING
        cur = cur[p]
    return cur


_MISSING = object()


def is_scalar(v):
    return not isinstance(v, (list, dict))


def scalar_eq(av, want):
    if not is_scalar(av):
        return False
    if is_number(av) and is_number(want):
        return float(av) == float(want)
    if isinstance(av, bool) != isinstance(want, bool):
        return False
    if type(av) != type(want) and not (is_number(av) and is_number(want)):
        return False
    return av == want


def glob_match(pat, s):
    p, t = list(pat), list(s)

    def go(i, j):
        if i == len(p):
            return j == len(t)
        if p[i] == '*':
            return go(i + 1, j) or (j < len(t) and go(i, j + 1))
        if p[i] == '?':
            return j < len(t) and go(i + 1, j + 1)
        return j < len(t) and t[j] == p[i] and go(i + 1, j + 1)

    return go(0, 0)


def compare(op, av, want):
    if op == 'Eq':
        return scalar_eq(av, want)
    if op == 'Ne':
        return not scalar_eq(av, want)
    if op in ('Gt', 'Lt', 'Ge', 'Le'):
        if not (is_number(av) and is_number(want)):
            return False
        a, b = float(av), float(want)
        return {'Gt': a > b, 'Lt': a < b, 'Ge': a >= b, 'Le': a <= b}[op]
    if op in ('In', 'NotIn'):
        found = isinstance(want, list) and any(scalar_eq(av, w) for w in want)
        return found if op == 'In' else not found
    if op == 'Contains':
        if isinstance(av, list):
            return any(scalar_eq(x, want) for x in av)
        if isinstance(av, str):
            return isinstance(want, str) and want in av
        return False
    if op == 'Regex':
        if isinstance(av, str) and isinstance(want, str):
            try:
                return re.search(want, av) is not None
            except re.error:
                return False
        return False
    if op == 'Glob':
        return isinstance(av, str) and isinstance(want, str) and glob_match(want, av)
    raise AssertionError(op)


def element_hit(sub, el):
    return evaluate(sub, el if isinstance(el, dict) else {'': el})


def as_i64(v):
    return v if isinstance(v, int) and not isinstance(v, bool) else None


def world_open(rule):
    return rule.get('cidr') == '0.0.0.0/0' and isinstance(rule.get('cidr'), str)


def sg_ports(attrs, ports):
    rules = attrs.get('ingress')
    if not isinstance(rules, list):
        return False
    for rule in rules:
        if not isinstance(rule, dict) or not world_open(rule):
            continue
        f, t = as_i64(rule.get('from_port')), as_i64(rule.get('to_port'))
        if f is not None and t is not None:
            if any(f <= p <= t for p in ports):
                return True
        elif f is not None or t is not None:
            p0 = f if f is not None else t
            if p0 in ports:
                return True
        else:
            return True
    return False


def sg_all(attrs):
    rules = attrs.get('ingress')
    if not isinstance(rules, list):
        return False
    return any(isinstance(r, dict) and world_open(r) and isinstance(r.get('protocol'), str) and r['protocol'].lower() in ('-1', 'all') for r in rules)


def star_in(p):
    if isinstance(p, str):
        return p == '*'
    if isinstance(p, dict):
        for v in p.values():
            if isinstance(v, list):
                if any(x == '*' and isinstance(x, str) for x in v):
                    return True
            elif isinstance(v, str) and v == '*':
                return True
        return False
    if isinstance(p, list):
        return any(isinstance(x, str) and x == '*' for x in p)
    return False


def iam_wild(attrs):
    policy = attrs.get('assume_role_policy')
    if not isinstance(policy, dict):
        return False
    st = policy.get('Statement')
    if isinstance(st, list):
        items = st
    elif isinstance(st, dict):
        items = [st]
    else:
        return False
    for s in items:
        if isinstance(s, dict) and s.get('Effect') == 'Allow' and isinstance(s.get('Effect'), str) and 'Principal' in s and star_in(s['Principal']):
            return True
    return False


def evaluate(f, attrs):
    k = f['kind']
    if k == 'And':
        return all(evaluate(c, attrs) for c in f['children'])
    if k == 'Or':
        return any(evaluate(c, attrs) for c in f['children'])
    if k == 'Not':
        return not evaluate(f['children'][0], attrs)
    if k == 'Builtin':
        name, args = f['name'], f['args']
        if name == 'sg_world_open_ports':
            ports = [as_i64(x) for x in args] if isinstance(args, list) else []
            return sg_ports(attrs, [p for p in ports if p is not None])
        if name == 'sg_world_open_all_protocols':
            return sg_all(attrs)
        if name == 'iam_wildcard_principal':
            return iam_wild(attrs)
        return False
    op = f['op']
    res = navigate(f['key'], attrs)
    if op == 'Present':
        return res is not _MISSING
    if op == 'Absent':
        return res is _MISSING
    if op in ('Any', 'All'):
        if not isinstance(res, list):
            return False
        hits = [element_hit(f['element'], x) for x in res]
        return any(hits) if op == 'Any' else all(hits)
    if op == 'Count':
        if not isinstance(res, list):
            return False
        n = sum(1 for x in res if element_hit(f['element'], x)) if f['element'] else len(res)
        return compare(f['count_op'] or 'Eq', n, f['value'])
    if res is _MISSING:
        return False
    return compare(op, res, f['value'])


def case(filter_value, attrs):
    try:
        f = parse(filter_value)
    except Refusal as e:
        return 'C ' + json.dumps({'filter': filter_value, 'attrs': attrs, 'error': str(e)}, separators=(',', ':'), ensure_ascii=False)
    return 'C ' + json.dumps({'filter': filter_value, 'attrs': attrs, 'expect': evaluate(f, attrs)}, separators=(',', ':'), ensure_ascii=False)


KEYS = ['a', 'b', 'tags', 'ports', 'ingress', 'name', 'n', 'flag']
STRINGS = ['prod', 'dev', 'x', '', 'petcow-prod-bucket', 'a b', 'é', '0.0.0.0/0', '10.0.0.0/8', '*', 'Allow', '-1', 'ALL']
PATTERNS = ['^petcow-', 'prod', 'b$', '^$', 'x|dev', '[a-c]+', 'p.od', '\\d', '[', '(', 'bucket$']
GLOBS = ['petcow-*-bucket', 'aws-*', '*', '?', 'p?od', '*d', 'é', '*b*', '']


def rand_scalar(rng):
    r = rng.random()
    if r < 0.3:
        return rng.randint(-2, 6)
    if r < 0.4:
        return rng.choice([0.5, 1.0, 2.5])
    if r < 0.5:
        return rng.choice([True, False, None])
    return rng.choice(STRINGS)


def rand_value(rng, depth=0):
    r = rng.random()
    if depth > 1 or r < 0.6:
        return rand_scalar(rng)
    if r < 0.8:
        return [rand_value(rng, depth + 1) for _ in range(rng.randint(0, 3))]
    return {rng.choice(KEYS): rand_value(rng, depth + 1) for _ in range(rng.randint(0, 3))}


def rand_attrs(rng):
    a = {}
    for k in rng.sample(KEYS, rng.randint(0, 6)):
        a[k] = rand_value(rng)
    if rng.random() < 0.3:
        a['ingress'] = [{'cidr': rng.choice(['0.0.0.0/0', '10.0.0.0/8']), 'from_port': rng.choice([0, 22, 3306, 80, None]), 'to_port': rng.choice([65535, 22, 443, None]),
                         'protocol': rng.choice(['-1', 'all', 'tcp', 'ALL'])} for _ in range(rng.randint(0, 3))]
        for rule in a['ingress']:
            for k in ('from_port', 'to_port'):
                if rule[k] is None:
                    del rule[k]
    if rng.random() < 0.2:
        a['assume_role_policy'] = {'Statement': rng.choice([[{'Effect': rng.choice(['Allow', 'Deny']), 'Principal': rng.choice(['*', {'AWS': '*'}, {'AWS': ['*']}, {'Service': 'ec2.amazonaws.com'}, ['*']])}],
                                                            {'Effect': 'Allow', 'Principal': '*'}, 'oops'])}
    return a


def rand_leaf(rng, depth):
    op = rng.choice(list(OPS))
    leaf = {'key': rng.choice(KEYS + ['tags.x', 'a.b', '', 'ports'])}
    if rng.random() < 0.9:
        leaf['op'] = op
    if op in ('regex', 'matches'):
        leaf['value'] = rng.choice(PATTERNS)
    elif op == 'glob':
        leaf['value'] = rng.choice(GLOBS)
    elif op in ('in', 'not_in', 'notin'):
        leaf['value'] = [rand_scalar(rng) for _ in range(rng.randint(0, 3))] if rng.random() < 0.9 else rand_scalar(rng)
    elif op == 'count':
        leaf['value'] = rng.choice([0, 1, 2, 3, 'big'])
        if rng.random() < 0.6:
            leaf['count_op'] = rng.choice(['gt', 'ge', 'le', 'lt', 'ne', 'eq', 'any', 'wat'])
    elif op not in ('present', 'exists', 'absent', 'missing', 'any', 'all') or rng.random() < 0.2:
        leaf['value'] = rand_scalar(rng)
    if op in ('any', 'all', 'count') and depth < 2 and rng.random() < 0.85:
        leaf['element'] = rand_filter(rng, depth + 1)
    return leaf


def rand_filter(rng, depth=0):
    r = rng.random()
    if depth < 2 and r < 0.15:
        return {'and': [rand_filter(rng, depth + 1) for _ in range(rng.randint(0, 3))]}
    if depth < 2 and r < 0.3:
        return {'or': [rand_filter(rng, depth + 1) for _ in range(rng.randint(0, 3))]}
    if depth < 2 and r < 0.4:
        return {'not': rand_filter(rng, depth + 1)}
    if r < 0.45:
        return {'builtin': rng.choice(['sg_world_open_ports', 'sg_world_open_all_protocols', 'iam_wildcard_principal', 'nope']),
                'args': rng.choice([[22, 3389], [3306, 5432], [], None, 'x'])}
    if r < 0.47:
        return rng.choice(['just a string', 3, None, ['x']])
    if r < 0.5:
        return {'and': [rand_filter(rng, depth + 1)], 'extra': 1}
    if r < 0.52:
        return {'and': 'x'}
    return rand_leaf(rng, depth)


def main():
    rng = random.Random(2505)
    lines = []
    # petcow's own tests
    b = {'count': 3}
    lines += [case({'key': 'count', 'op': 'eq', 'value': 3}, b), case({'key': 'count', 'value': 3.0}, b), case({'key': 'count', 'op': 'ne', 'value': 4}, b),
              case({'key': 'count', 'op': 'eq', 'value': 4}, b)]
    lines += [case({'key': 'versioning', 'op': 'present'}, {'versioning': True}), case({'key': 'nope', 'op': 'absent'}, {'versioning': True}),
              case({'key': 'versioning', 'op': 'absent'}, {'versioning': True})]
    s = {'size': 100}
    lines += [case({'key': 'size', 'op': 'gt', 'value': 50}, s), case({'key': 'size', 'op': 'ge', 'value': 100}, s), case({'key': 'size', 'op': 'lt', 'value': 100}, s),
              case({'key': 'size', 'op': 'gt', 'value': 'hello'}, s)]
    e = {'env': 'prod', 'ports': [22, 443]}
    lines += [case({'key': 'env', 'op': 'in', 'value': ['dev', 'prod']}, e), case({'key': 'env', 'op': 'in', 'value': ['dev', 'stage']}, e),
              case({'key': 'ports', 'op': 'contains', 'value': 22}, e), case({'key': 'env', 'op': 'contains', 'value': 'pro'}, e)]
    n = {'name': 'petcow-prod-bucket'}
    lines += [case({'key': 'name', 'op': 'regex', 'value': '^petcow-'}, n), case({'key': 'name', 'op': 'glob', 'value': 'petcow-*-bucket'}, n),
              case({'key': 'name', 'op': 'glob', 'value': 'aws-*'}, n), case({'key': 'name', 'op': 'regex', 'value': '['}, n)]
    pv = {'public': True, 'versioning': False}
    lines += [case({'and': [{'key': 'public', 'value': True}, {'key': 'versioning', 'value': False}]}, pv),
              case({'or': [{'key': 'public', 'value': False}, {'key': 'versioning', 'value': False}]}, pv),
              case({'not': {'key': 'public', 'value': False}}, pv), case({'not': {'key': 'public', 'value': True}}, pv)]
    rule = {'cidr': '0.0.0.0/0', 'from_port': 22, 'to_port': 22}
    f = {'key': 'ingress', 'op': 'any', 'element': {'and': [{'key': 'cidr', 'value': '0.0.0.0/0'}, {'key': 'from_port', 'op': 'le', 'value': 22}, {'key': 'to_port', 'op': 'ge', 'value': 22}]}}
    lines.append(case(f, {'ingress': [rule]}))
    two = {'ingress': [{'cidr': '0.0.0.0/0'}, {'cidr': '10.0.0.0/8'}]}
    lines += [case({'key': 'ingress', 'op': 'any', 'element': {'key': 'cidr', 'value': '0.0.0.0/0'}}, two),
              case({'key': 'ingress', 'op': 'all', 'element': {'key': 'cidr', 'value': '0.0.0.0/0'}}, two),
              case({'key': 'ingress', 'op': 'all', 'element': {'key': 'cidr', 'value': 'x'}}, {'ingress': []}),
              case({'key': 'ingress', 'op': 'any', 'element': {'key': 'cidr', 'value': 'x'}}, {'ingress': []})]
    ing = {'ingress': [22, 443, 80]}
    lines += [case({'key': 'ingress', 'op': 'count', 'value': 3}, ing), case({'key': 'ingress', 'op': 'count', 'value': 2}, ing),
              case({'key': 'ingress', 'op': 'count', 'value': 2, 'count_op': 'gt'}, ing), case({'key': 'ingress', 'op': 'count', 'value': 3, 'count_op': 'ge'}, ing),
              case({'key': 'nope', 'op': 'count', 'value': 0}, ing)]
    wo = {'ingress': [{'cidr': '0.0.0.0/0'}, {'cidr': '0.0.0.0/0'}, {'cidr': '10.0.0.0/8'}]}
    lines += [case({'key': 'ingress', 'op': 'count', 'count_op': 'ge', 'value': 2, 'element': {'key': 'cidr', 'value': '0.0.0.0/0'}}, wo),
              case({'key': 'ingress', 'op': 'count', 'count_op': 'ge', 'value': 3, 'element': {'key': 'cidr', 'value': '0.0.0.0/0'}}, wo)]
    lines += [case({'key': 'tags.Environment', 'value': 'prod'}, {'tags': {'Environment': 'prod'}}), case({'key': 'tags.Owner', 'op': 'absent'}, {'tags': {'Environment': 'prod'}})]
    for bad in ('just a string', {'key': 'x', 'op': 'any'}, {'key': 'x', 'op': 'gt'}, {'key': 'x', 'op': 'wat', 'value': 1}, {'key': 'x', 'op': 'count', 'value': 'big'},
                {'key': 'x', 'op': 'count', 'value': 1, 'count_op': 'any'}, {'key': 'x'}, {'op': 'eq', 'value': 1}, {'and': [{'key': 'a', 'value': 1}], 'or': []}):
        lines.append(case(bad, {}))
    # built-ins (petcow's predicate tests)
    open_range = {'ingress': [{'cidr': '0.0.0.0/0', 'from_port': 0, 'to_port': 65535}]}
    lines += [case({'builtin': 'sg_world_open_ports', 'args': [22, 3389]}, open_range), case({'builtin': 'sg_world_open_ports', 'args': [22]}, {}),
              case({'builtin': 'sg_world_open_ports', 'args': [22]}, {'ingress': [{'cidr': '0.0.0.0/0'}]}),
              case({'builtin': 'sg_world_open_all_protocols'}, {'ingress': [{'cidr': '0.0.0.0/0', 'protocol': '-1'}]}),
              case({'builtin': 'iam_wildcard_principal'}, {'assume_role_policy': {'Statement': [{'Effect': 'Allow', 'Principal': '*'}]}}),
              case({'builtin': 'does_not_exist'}, {'ingress': [{'cidr': '0.0.0.0/0'}]})]
    for _ in range(900):
        lines.append(case(rand_filter(rng), rand_attrs(rng)))
    here = pathlib.Path(__file__).resolve().parent
    chunks = ['"' + '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"') for l in lines[i:i + 40]) + '\\n"' for i in range(0, len(lines), 40)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    template = (here / 'predicate_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'algo_predicate' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    errors = sum(1 for l in lines if '"error"' in l)
    trues = sum(1 for l in lines if '"expect":true' in l)
    print('wrote', len(lines), 'cases:', trues, 'true,', len(lines) - trues - errors, 'false,', errors, 'refused')


main()
