"""Write tests/selfhost/fixtures/link/math_units/src/main.e (L077, D2267).

  python scripts/units_reference.py

e.math.units against exact rational definitions. The reference rebuilds every unit's factor from its
definition as a Fraction (inch = 254/10000 m, the pound = 0.45359237 kg, the US gallon = 231 in^3, the
acre = 43560 ft^2, a bit = 1/8 byte, ...), so the library's decimal literals are checked against
definitions, not against themselves. Every ordered pair of units in each family is converted for a
non-trivial value and compared at 1e-13 relative (temperature adds an absolute floor); identities
(1 mi = 5280 ft, 1 lb = 16 oz, 100 C = 212 F, ...), round trips, the registry (custom family,
Duplicate, Invalid, TooSmall, Unknown, Incompatible), non-finite and overflowing values are checked too.
A mismatch prints its table and index and exits 1.
"""
import math
import pathlib
from fractions import Fraction as Fr

import numpy as np
import scipy.constants as sc

root = pathlib.Path(__file__).resolve().parent.parent
rng = np.random.default_rng(20261019)

inch = Fr(254, 10000)
foot = 12 * inch
yard = 3 * foot
mile = 5280 * foot
gal = 231 * inch ** 3
lb = Fr(45359237, 100000000)
oz = lb / 16
day = Fr(86400)
au = Fr(149597870700)
c_light = 299792458
ly = c_light * day * Fr(36525, 100)

length = {'m': Fr(1), 'km': Fr(1000), 'cm': Fr(1, 100), 'mm': Fr(1, 1000), 'um': Fr(1, 10 ** 6), 'nm': Fr(1, 10 ** 9),
          'mi': mile, 'yd': yard, 'ft': foot, 'in': inch, 'nmi': Fr(1852), 'au': au, 'ly': ly}
area = {'m2': Fr(1), 'km2': Fr(10 ** 6), 'cm2': Fr(1, 10 ** 4), 'mm2': Fr(1, 10 ** 6), 'ha': Fr(10 ** 4), 'ac': 43560 * foot ** 2,
        'ft2': foot ** 2, 'in2': inch ** 2, 'yd2': yard ** 2, 'mi2': mile ** 2}
volume = {'m3': Fr(1), 'L': Fr(1, 1000), 'mL': Fr(1, 10 ** 6), 'cm3': Fr(1, 10 ** 6), 'gal': gal, 'qt': gal / 4, 'pt': gal / 8,
          'cup': gal / 16, 'floz': gal / 128, 'tbsp': gal / 256, 'tsp': gal / 768, 'gal_uk': Fr(454609, 10 ** 8),
          'ft3': foot ** 3, 'in3': inch ** 3}
mass = {'kg': Fr(1), 'g': Fr(1, 1000), 'mg': Fr(1, 10 ** 6), 'ug': Fr(1, 10 ** 9), 't': Fr(1000), 'lb': lb, 'oz': oz,
        'st': 14 * lb, 'ton_us': 2000 * lb, 'ton_uk': 2240 * lb, 'ct': Fr(2, 10000), 'gr': lb / 7000}
time = {'s': Fr(1), 'ms': Fr(1, 1000), 'us': Fr(1, 10 ** 6), 'ns': Fr(1, 10 ** 9), 'min': Fr(60), 'h': Fr(3600), 'd': day,
        'wk': 7 * day, 'yr': Fr(36525, 100) * day}
data = {'B': Fr(1), 'kB': Fr(1000), 'MB': Fr(10 ** 6), 'GB': Fr(10 ** 9), 'TB': Fr(10 ** 12), 'PB': Fr(10 ** 15), 'KiB': Fr(2 ** 10),
        'MiB': Fr(2 ** 20), 'GiB': Fr(2 ** 30), 'TiB': Fr(2 ** 40), 'PiB': Fr(2 ** 50), 'bit': Fr(1, 8), 'kbit': Fr(1000, 8),
        'Mbit': Fr(10 ** 6, 8), 'Gbit': Fr(10 ** 9, 8)}
# temperature: (scale, offset) with kelvin = value * scale + offset
temperature = {'K': (Fr(1), Fr(0)), 'C': (Fr(1), Fr(27315, 100)), 'F': (Fr(5, 9), Fr(45967, 100) * Fr(5, 9)),
               'R': (Fr(5, 9), Fr(0)), 'Re': (Fr(5, 4), Fr(27315, 100))}
families = {'length': length, 'area': area, 'volume': volume, 'mass': mass, 'time': time, 'data': data}
families_with_pc = dict(length=length)

# the library's irrational and tabulated factors are checked against scipy as a second authority
assert abs(float(foot) - sc.foot) < 1e-15 and abs(float(lb) - sc.pound) < 1e-15 and abs(float(gal) - sc.gallon) < 1e-15
assert abs(float(ly) - sc.light_year) / sc.light_year < 1e-15 and abs(float(mile) - sc.mile) < 1e-12
assert abs(float(43560 * foot ** 2) - sc.acre) < 1e-9 and abs(float(Fr(36525, 100) * day) - sc.Julian_year) < 1e-6
assert abs(float(14 * lb) - sc.stone) < 1e-12 and abs(float(2000 * lb) - sc.short_ton) < 1e-9 and abs(float(2240 * lb) - sc.long_ton) < 1e-9
assert abs(float(lb / 7000) - sc.grain) < 1e-12 and abs(float(gal / 128) - sc.fluid_ounce) < 1e-12

lines = []


def quote(s):
    return '"' + s + '"'


def fnum(x):
    return repr(float(x)) + 'f64'


def table(name, rows):
    """rows: (from, to, value, expected, tolerance)."""
    lines.append('    let %s_from = [%d]str{ %s }' % (name, len(rows), ', '.join(quote(r[0]) for r in rows)))
    lines.append('    let %s_to = [%d]str{ %s }' % (name, len(rows), ', '.join(quote(r[1]) for r in rows)))
    lines.append('    let %s_value = [%d]f64{ %s }' % (name, len(rows), ', '.join(fnum(r[2]) for r in rows)))
    lines.append('    let %s_want = [%d]f64{ %s }' % (name, len(rows), ', '.join(fnum(r[3]) for r in rows)))
    lines.append('    let %s_floor = [%d]f64{ %s }' % (name, len(rows), ', '.join(fnum(r[4]) for r in rows)))
    lines.append('    var %s_i = 0usize' % name)
    lines.append('    while %s_i < %d {' % (name, len(rows)))
    lines.append('        let (%s_got, %s_error) = units.convert(&reg, %s_value[%s_i], %s_from[%s_i], %s_to[%s_i])' % ((name,) * 2 + (name,) * 6))
    lines.append('        if %s_error != ok || !close(%s_got, %s_want[%s_i], %s_floor[%s_i]) { try report("%s", %s_i) }' % ((name,) * 2 + (name,) * 5 + (name,)))
    lines.append('        %s_i += 1usize' % name)
    lines.append('    }')


lines.append('    var storage: [100]units.Unit = zero')
lines.append('    let (reg_made, reg_error) = units.registry(storage[..])')
lines.append('    if reg_error != ok || reg_made.count != 79usize || units.builtin_count() != 79usize { try report("registry", 0usize) }')
lines.append('    var reg = reg_made')

for index, (fname, fam) in enumerate(families.items()):
    syms = list(fam)
    rows = []
    v = Fr(37, 10)
    for a in syms:
        for b in syms:
            rows.append((a, b, float(v), float(v * fam[a] / fam[b]), 0.0))
    table('pairs_%s' % fname, rows)
# temperature: all ordered pairs for three readings
rows = []
for v in (Fr(37, 10), Fr(-40), Fr(0)):
    for a, (sa, oa) in temperature.items():
        for b, (sb, ob) in temperature.items():
            rows.append((a, b, float(v), float((v * sa + oa - ob) / sb), 1e-9))
table('pairs_temperature', rows)
# parsec: the one irrational factor, against scipy
rows = [('pc', 'm', 1.0, sc.parsec, 0.0), ('pc', 'ly', 1.0, sc.parsec / sc.light_year, 0.0), ('pc', 'au', 1.0, sc.parsec / sc.astronomical_unit, 0.0)]
table('parsec', rows)

# identities (each an exact relation between units, tolerance 1e-13 relative)
ident = [('mi', 'ft', 1, 5280), ('ft', 'in', 1, 12), ('yd', 'ft', 1, 3), ('lb', 'oz', 1, 16), ('st', 'lb', 1, 14), ('ton_us', 'lb', 1, 2000),
         ('ton_uk', 'lb', 1, 2240), ('oz', 'gr', 1, 437.5), ('gal', 'in3', 1, 231), ('gal', 'qt', 1, 4), ('gal', 'cup', 1, 16), ('cup', 'tbsp', 1, 16),
         ('tbsp', 'tsp', 1, 3), ('cup', 'floz', 1, 8), ('L', 'cm3', 1, 1000), ('m3', 'L', 1, 1000), ('ac', 'ft2', 1, 43560), ('ha', 'm2', 1, 10000),
         ('km2', 'ha', 1, 100), ('h', 's', 1, 3600), ('d', 'h', 1, 24), ('wk', 'd', 1, 7), ('yr', 'd', 1, 365.25), ('min', 'ms', 1, 60000),
         ('GiB', 'MiB', 1, 1024), ('GB', 'MB', 1, 1000), ('B', 'bit', 1, 8), ('MiB', 'KiB', 1, 1024), ('kbit', 'bit', 1, 1000), ('PiB', 'TiB', 1, 1024),
         ('nmi', 'm', 1, 1852), ('km', 'm', 1, 1000), ('in', 'mm', 1, 25.4), ('lb', 'g', 1, 453.59237), ('gal_uk', 'L', 1, 4.54609), ('ct', 'mg', 1, 200)]
table('identity', [(a, b, v, w, 0.0) for a, b, v, w in ident])
temps = [('C', 'F', 100, 212), ('C', 'F', -40, -40), ('F', 'C', -40, -40), ('K', 'C', 0, -273.15), ('C', 'K', 0, 273.15), ('F', 'C', 32, 0),
         ('C', 'R', 0, 491.67), ('K', 'R', 100, 180), ('C', 'Re', 100, 80), ('Re', 'C', 80, 100), ('F', 'K', 212, 373.15)]
table('temperature_known', [(a, b, v, w, 1e-9) for a, b, v, w in temps])

# round trips over random pairs inside each family
rt = []
for fname, fam in families.items():
    syms = list(fam)
    for _ in range(40):
        a, b = rng.choice(syms, 2)
        v = float(np.round(rng.uniform(0.001, 5000.0), 4))
        rt.append((str(a), str(b), v))
lines.append('    let rt_from = [%d]str{ %s }' % (len(rt), ', '.join(quote(r[0]) for r in rt)))
lines.append('    let rt_to = [%d]str{ %s }' % (len(rt), ', '.join(quote(r[1]) for r in rt)))
lines.append('    let rt_value = [%d]f64{ %s }' % (len(rt), ', '.join(fnum(r[2]) for r in rt)))
lines.append('    var rt_i = 0usize')
lines.append('    while rt_i < %d {' % len(rt))
lines.append('        let (rt_there, rt_there_error) = units.convert(&reg, rt_value[rt_i], rt_from[rt_i], rt_to[rt_i])')
lines.append('        let (rt_back, rt_back_error) = units.convert(&reg, rt_there, rt_to[rt_i], rt_from[rt_i])')
lines.append('        if rt_there_error != ok || rt_back_error != ok || !close(rt_back, rt_value[rt_i], 0.0f64) { try report("roundtrip", rt_i) }')
lines.append('        rt_i += 1usize')
lines.append('    }')
# identity conversion is exact, even for awkward values
lines.append('    let (same_one, same_error) = units.convert(&reg, 1.0000000000000002f64, "in", "in")')
lines.append('    if same_error != ok || same_one != 1.0000000000000002f64 { try report("same-unit", 0usize) }')
lines.append('    let (same_big, same_big_error) = units.convert(&reg, 1.0e308f64, "kg", "kg")')
lines.append('    if same_big_error != ok || same_big != 1.0e308f64 { try report("same-unit", 1usize) }')

# every built-in is well formed and the family counts match the tables
lines.append('    var seen = 0usize')
lines.append('    while seen < units.builtin_count() {')
lines.append('        let bu = units.builtin(seen)')
lines.append('        if bu.symbol.len == 0usize || bu.name.len == 0usize || bu.family == 0u32 || !(bu.scale > 0.0f64) { try report("builtin", seen) }')
lines.append('        var other = 0usize')
lines.append('        while other < seen {')
lines.append('            if units.same(units.builtin(other).symbol, bu.symbol) { try report("duplicate-symbol", seen) }')
lines.append('            other += 1usize')
lines.append('        }')
lines.append('        seen += 1usize')
lines.append('    }')
lines.append('    let empty_unit = units.builtin(79usize)')
lines.append('    if empty_unit.symbol.len != 0usize || empty_unit.family != 0u32 { try report("builtin-past-end", 0usize) }')
counts = [('LENGTH', 14), ('AREA', 10), ('VOLUME', 14), ('MASS', 12), ('TIME', 9), ('TEMPERATURE', 5), ('DATA', 15)]
lines.append('    var members: [20]usize = zero')
for k, (fam, expect) in enumerate(counts):
    lines.append('    let (count_%d, count_%d_error) = units.family_units(&reg, units.%s, members[..])' % (k, k, fam))
    lines.append('    if count_%d_error != ok || count_%d != %dusize { try report("family-count", %dusize) }' % (k, k, expect, k))
lines.append('    let (_, small_count_error) = units.family_units(&reg, units.LENGTH, members[..5usize])')
lines.append('    if small_count_error != units.TooSmall { try report("family-units-room", 0usize) }')
lines.append('    let (no_count, no_count_error) = units.family_units(&reg, 99u32, members[..])')
lines.append('    if no_count_error != ok || no_count != 0usize { try report("family-none", 0usize) }')
lines.append('    if !units.same(units.family_name(units.TEMPERATURE), "temperature") || !units.same(units.family_name(units.DATA), "data") || units.family_name(55u32).len != 0usize { try report("family-name", 0usize) }')

# registry behaviour: custom family, errors
lines.append('    let pi = 3.141592653589793f64')
lines.append('    let custom_ok = units.register(&reg, units.Unit { symbol: "rad", name: "radian", family: 101u32, scale: 1.0f64, offset: 0.0f64 })')
lines.append('    let custom_deg = units.register(&reg, units.Unit { symbol: "deg", name: "degree", family: 101u32, scale: pi / 180.0f64, offset: 0.0f64 })')
lines.append('    let custom_grad = units.register(&reg, units.Unit { symbol: "grad", name: "gradian", family: 101u32, scale: pi / 200.0f64, offset: 0.0f64 })')
lines.append('    if custom_ok != ok || custom_deg != ok || custom_grad != ok || reg.count != 82usize { try report("register", 0usize) }')
lines.append('    let (deg_rad, deg_rad_error) = units.convert(&reg, 180.0f64, "deg", "rad")')
lines.append('    let (grad_deg, grad_deg_error) = units.convert(&reg, 100.0f64, "grad", "deg")')
lines.append('    if deg_rad_error != ok || !close(deg_rad, pi, 0.0f64) || grad_deg_error != ok || !close(grad_deg, 90.0f64, 0.0f64) { try report("custom-convert", 0usize) }')
lines.append('    let (angle_count, angle_error) = units.family_units(&reg, 101u32, members[..])')
lines.append('    if angle_error != ok || angle_count != 3usize || members[0usize] != 79usize { try report("custom-family", 0usize) }')
lines.append('    let (_, angle_length) = units.convert(&reg, 1.0f64, "deg", "m")')
lines.append('    let (_, length_angle) = units.convert(&reg, 1.0f64, "m", "rad")')
lines.append('    if angle_length != units.Incompatible || length_angle != units.Incompatible { try report("incompatible", 0usize) }')
lines.append('    let (_, mass_time) = units.convert(&reg, 1.0f64, "kg", "s")')
lines.append('    let (_, temp_data) = units.convert(&reg, 1.0f64, "C", "B")')
lines.append('    if mass_time != units.Incompatible || temp_data != units.Incompatible { try report("incompatible", 1usize) }')
lines.append('    let dup = units.register(&reg, units.Unit { symbol: "m", name: "again", family: 1u32, scale: 1.0f64, offset: 0.0f64 })')
lines.append('    let dup_custom = units.register(&reg, units.Unit { symbol: "rad", name: "again", family: 101u32, scale: 1.0f64, offset: 0.0f64 })')
lines.append('    if dup != units.Duplicate || dup_custom != units.Duplicate { try report("duplicate", 0usize) }')
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    let inf = 1.0f64 / zero_f64()')
bad = [('symbol: "", name: "x", family: 9u32, scale: 1.0f64, offset: 0.0f64', 'empty-symbol'),
       ('symbol: "z1", name: "x", family: 0u32, scale: 1.0f64, offset: 0.0f64', 'family-zero'),
       ('symbol: "z2", name: "x", family: 9u32, scale: 0.0f64, offset: 0.0f64', 'scale-zero'),
       ('symbol: "z3", name: "x", family: 9u32, scale: nan, offset: 0.0f64', 'scale-nan'),
       ('symbol: "z4", name: "x", family: 9u32, scale: inf, offset: 0.0f64', 'scale-inf'),
       ('symbol: "z5", name: "x", family: 9u32, scale: 1.0f64, offset: nan', 'offset-nan'),
       ('symbol: "z6", name: "x", family: 9u32, scale: 1.0f64, offset: inf', 'offset-inf')]
for k, (fields, label) in enumerate(bad):
    lines.append('    let bad_%d = units.register(&reg, units.Unit { %s })' % (k, fields))
    lines.append('    if bad_%d != units.Invalid { try report("%s", 0usize) }' % (k, label))
lines.append('    if reg.count != 82usize { try report("register-rejected-grew", 0usize) }')
lines.append('    let (_, unknown_from) = units.convert(&reg, 1.0f64, "parsecs", "m")')
lines.append('    let (_, unknown_to) = units.convert(&reg, 1.0f64, "m", "furlong")')
lines.append('    let (_, unknown_case) = units.convert(&reg, 1.0f64, "M", "m")')
lines.append('    let (_, unknown_empty) = units.convert(&reg, 1.0f64, "", "m")')
lines.append('    if unknown_from != units.Unknown || unknown_to != units.Unknown || unknown_case != units.Unknown || unknown_empty != units.Unknown { try report("unknown", 0usize) }')
lines.append('    let (_, value_nan) = units.convert(&reg, nan, "m", "ft")')
lines.append('    let (_, value_inf) = units.convert(&reg, inf, "m", "ft")')
lines.append('    let (_, value_overflow) = units.convert(&reg, 1.0e308f64, "PB", "bit")')
lines.append('    let (_, value_overflow_c) = units.convert(&reg, 1.7e308f64, "Re", "K")')
lines.append('    if value_nan != units.Invalid || value_inf != units.Invalid || value_overflow != units.Invalid || value_overflow_c != units.Invalid { try report("non-finite", 0usize) }')
lines.append('    var tiny: [78]units.Unit = zero')
lines.append('    let (_, tiny_error) = units.registry(tiny[..])')
lines.append('    if tiny_error != units.TooSmall { try report("registry-room", 0usize) }')
lines.append('    var snug: [80]units.Unit = zero')
lines.append('    let (snug_made, snug_error) = units.registry(snug[..])')
lines.append('    var snug_reg = snug_made')
lines.append('    let snug_one = units.register(&snug_reg, units.Unit { symbol: "a1", name: "x", family: 9u32, scale: 2.0f64, offset: 0.0f64 })')
lines.append('    let snug_two = units.register(&snug_reg, units.Unit { symbol: "a2", name: "x", family: 9u32, scale: 3.0f64, offset: 0.0f64 })')
lines.append('    if snug_error != ok || snug_one != ok || snug_two != units.TooSmall || snug_reg.count != 80usize { try report("register-room", 0usize) }')
lines.append('    let (a1_a1, a1_error) = units.convert(&snug_reg, 6.0f64, "a1", "a1")')
lines.append('    if a1_error != ok || a1_a1 != 6.0f64 { try report("custom-same", 0usize) }')

body = '\n'.join(lines)
source = '''// e.math.units against exact rational definitions (L077, D2267; scripts/units_reference.py writes
// this file): every ordered pair of units in each family for a non-trivial value, parsec against scipy,
// 36 unit identities, 11 known temperature readings, random round trips, the registry (a custom angle
// family, Duplicate, Invalid, Unknown, Incompatible, TooSmall), and non-finite and overflowing values. A
// mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.math.units

fn zero_f64() -> f64 { ret 0.0f64 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// Relative 1e-13, plus an absolute floor for readings that cancel.
fn close(got: f64, want: f64, floor: f64) -> bool {
    ret abs64(got - want) <= 1e-13f64 * abs64(want) + floor
}

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 0u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("units mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i])..usize(digits[i]) + 1usize])
    }
    try io.print("\\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("math units ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'math_units' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote math_units;', sum(len(f) ** 2 for f in families.values()) + 3 * 25, 'pair conversions + identities + round trips')
