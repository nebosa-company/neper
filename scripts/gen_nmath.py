#!/usr/bin/env python3
"""Writes lib/e/math/nmath.e from scripts/nmath_template.e.txt, copying the coefficient tables
of R's nmath (gamma.c, lgammacor.c, stirlerr.c, pgamma.c) out of the C sources:
  python scripts/gen_nmath.py <R src/nmath directory> > lib/e/math/nmath.e"""
import re, sys

d = sys.argv[1].rstrip('/') + '/'


def table(path, name, n, var, indent):
    s = open(d + path).read()
    i = s.index(name)
    i = s.index('{', i)
    j = s.index('};', i)
    body = re.sub(r'/\*.*?\*/', '', s[i + 1:j], flags=re.S)
    body = re.sub(r'//[^\n]*', '', body)
    toks = [t.strip() for t in body.replace('\n', ' ').split(',') if t.strip()]
    out = []
    for k, x in enumerate(toks[:n]):
        x = x.lstrip('+')
        neg = x.startswith('-')
        x = x.lstrip('-')
        if x.startswith('.'):
            x = '0' + x
        if re.fullmatch(r'\d+', x):
            x += '.0'
        out.append('%s%s[%dusize] = %s%sf64' % (' ' * indent, var, k, '-' if neg else '', x))
    return '\n'.join(out)


t = open('scripts/nmath_template.e.txt').read()
t = t.replace('{GAMCS}', table('gamma.c', 'gamcs[42]', 22, 'g', 4))
t = t.replace('{ALGMCS}', table('lgammacor.c', 'algmcs[15]', 5, 'a', 4))
t = t.replace('{SFERR}', table('stirlerr.c', 'sferr_halves[31]', 31, 't', 12))
t = t.replace('{LGCOEF}', table('pgamma.c', 'coeffs[40]', 40, 'c', 4))
sys.stdout.write(t)
