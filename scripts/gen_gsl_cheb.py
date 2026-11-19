"""Generates lib/e/algo/stat/gslcheb.e from the Chebyshev tables of the GSL 2.7.1 specfunc sources.

Each table `static double X_data[n] = {...}; static cheb_series X_cs = { X_data, order, a, b, order_sp };` becomes an entry of ctab(id, k). cheb_eval is gsl's cheb_eval_e
and cheb_eval_mode gsl's cheb_eval_mode_e. The id, order, order_sp and interval of a table are returned by tid_/tord_/tsp_/ta_/tb_<file>_<X>().
"""
import re, sys

SRC = 'D:/Temp/claude/src/gslsrc/gsl-2.7.1/specfunc/'
OUT = 'D:/repos/neper/.claude/worktrees/agent-a8603e5300567a51d/lib/e/algo/stat/gslcheb.e'
FILES = sys.argv[1:] if len(sys.argv) > 1 else ['dawson', 'clausen', 'expint', 'airy', 'airy_der', 'bessel_I0', 'bessel_I1', 'bessel_K0', 'bessel_K1', 'zeta', 'bessel_J0', 'bessel_J1', 'bessel_Y0', 'bessel_Y1', 'bessel_amp_phase', 'erfc', 'psi', 'atanint', 'expint3', 'shint', 'sinint', 'debye']

tables = []
polys = []
for f in FILES:
    s = open(SRC + f + '.c', encoding='utf8').read()
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    for cm in re.finditer(r'(?:static\s+)?(?:const\s+)?cheb_series\s+(\w+)_cs\s*=\s*\{\s*(\w+)\s*,([^}]*)\}', s):
        name, data_id = cm.group(1), cm.group(2)
        m = re.search(r'static\s+double\s+' + data_id + r'\s*\[[^\]]*\]\s*=\s*\{(.*?)\};', s, flags=re.S)
        body = m.group(1)
        vals = [v.strip() for v in body.split(',') if v.strip()]
        fields = [x.strip() for x in cm.group(3).split(',') if x.strip()]
        order = int(fields[0]); a = fields[1]; b = fields[2]
        order_sp = int(fields[3]) if len(fields) > 3 else order
        tables.append((f + '_' + name, vals, order, a, b, order_sp))
    used = set(cm.group(2) for cm in re.finditer(r'(?:static\s+)?(?:const\s+)?cheb_series\s+(\w+)_cs\s*=\s*\{\s*(\w+)\s*,', s))
    for pm in re.finditer(r'static\s+(?:const\s+)?double\s+(\w+)\s*\[\s*\d*\s*\]\s*=\s*\{([^}]*)\}\s*;', s):
        if pm.group(1) in used or pm.group(1).endswith('_data') and f in ('dawson', 'clausen', 'expint', 'airy', 'airy_der'):
            continue
        polys.append((f + '_' + pm.group(1), [v.strip() for v in pm.group(2).split(',') if v.strip()]))


def lit(v):
    v = v.strip()
    if re.fullmatch(r'[-+]?\d+', v):
        v += '.0'
    v = re.sub(r'^([-+]?)\.', r'\g<1>0.', v)
    v = v.lstrip('+')
    return v + 'f64'


o = []
o.append("// Chebyshev coefficient tables of gsl 2.7.1 (specfunc/%s.c), generated from its source by a script, with gsl's cheb_eval_e and cheb_eval_mode_e." % ', '.join(FILES))
o.append('// cheb_eval(id, order, a, b, x) returns (value, error): error = eps * sum |terms| + |c[order]|; cheb_eval_mode(id, order, order_sp, a, b, x, mode) is the mode form: error = eps |value| + |c[order used]|.')
o.append('')
o.append('use e.math')
o.append('')
for i, (n, vals, order, a, b, osp) in enumerate(tables):
    o.append('fn tid_%s() -> usize { ret %dusize }' % (n, i))
    o.append('fn tord_%s() -> usize { ret %dusize }' % (n, order))
    o.append('fn tsp_%s() -> usize { ret %dusize }' % (n, osp))
    o.append('fn ta_%s() -> f64 { ret %s }' % (n, lit(a)))
    o.append('fn tb_%s() -> f64 { ret %s }' % (n, lit(b)))
o.append('')
o.append('fn ctab(id: usize, k: usize) -> f64 {')
for i, (n, vals, order, a, b, osp) in enumerate(tables):
    o.append('    if id == %dusize {' % i)
    for k, v in enumerate(vals):
        o.append('        if k == %dusize { ret %s }' % (k, lit(v)))
    o.append('    }')
o.append('    ret 0.0f64')
o.append('}')
o.append('')
o.append('''fn cheb_eval(id: usize, order: usize, a: f64, b: f64, x: f64) -> (f64, f64) {
    var d = 0.0f64
    var dd = 0.0f64
    let y = (2.0f64 * x - a - b) / (b - a)
    let y2 = 2.0f64 * y
    var e = 0.0f64
    var j = order
    while j >= 1usize {
        let temp = d
        let cj = ctab(id, j)
        d = y2 * d - dd + cj
        e += math.abs[f64](y2 * temp) + math.abs[f64](dd) + math.abs[f64](cj)
        dd = temp
        j -= 1usize
    }
    let temp = d
    let c0 = ctab(id, 0usize)
    d = y * d - dd + 0.5f64 * c0
    e += math.abs[f64](y * temp) + math.abs[f64](dd) + 0.5f64 * math.abs[f64](c0)
    ret (d, 2.2204460492503131e-16f64 * e + math.abs[f64](ctab(id, order)))
}

fn cheb_eval_mode(id: usize, order: usize, order_sp: usize, a: f64, b: f64, x: f64, mode: usize) -> (f64, f64) {
    var d = 0.0f64
    var dd = 0.0f64
    let y = (2.0f64 * x - a - b) / (b - a)
    let y2 = 2.0f64 * y
    var eval_order = order_sp
    if mode % 8usize == 0usize { eval_order = order }
    var j = eval_order
    while j >= 1usize {
        let temp = d
        d = y2 * d - dd + ctab(id, j)
        dd = temp
        j -= 1usize
    }
    let v = y * d - dd + 0.5f64 * ctab(id, 0usize)
    ret (v, 2.2204460492503131e-16f64 * math.abs[f64](v) + math.abs[f64](ctab(id, eval_order)))
}''')
o.append('')
for i, (n, vals, order, a, b, osp) in enumerate(tables):
    o.append('fn cev_%s(x: f64, mode: usize) -> (f64, f64) {' % n)
    o.append('    let (v, e) = cheb_eval_mode(%dusize, %dusize, %dusize, %s, %s, x, mode)' % (i, order, osp, lit(a), lit(b)))
    o.append('    ret (v, e)')
    o.append('}')
    o.append('')
    o.append('fn cvv_%s(x: f64) -> (f64, f64) {' % n)
    o.append('    let (v, e) = cheb_eval(%dusize, %dusize, %s, %s, x)' % (i, order, lit(a), lit(b)))
    o.append('    ret (v, e)')
    o.append('}')
    o.append('')
for (n, vals) in polys:
    o.append('// gsl_poly_eval of %s' % n)
    o.append('fn pv_%s(x: f64) -> f64 {' % n)
    expr = lit(vals[-1])
    for v in reversed(vals[:-1]):
        expr = '%s + x * (%s)' % (lit(v), expr)
    o.append('    ret %s' % expr)
    o.append('}')
    o.append('')
open(OUT, 'w', encoding='utf8', newline='').write('\n'.join(o) + '\n')
print(len(tables), 'tables', sum(len(t[1]) for t in tables), 'coefficients')
