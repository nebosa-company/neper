"""Write tests/selfhost/fixtures/link/fmt_xsd_types/src/main.e (L081, D2271, part 1: built-in datatypes).

  python scripts/xsd_datatype_reference.py

e.fmt.xsd.valid against libxml2's schema validator through lxml. For each of the 40 built-in types a
schema `<xs:element name="e" type="xs:T"/>` validates `<e>candidate</e>`; the verdict is the expected
value. Candidates are hand-picked boundaries and seeded mutations of valid forms (inserted, deleted and
replaced characters, whitespace padding, non-ASCII name characters), deduplicated, so the library is
checked on both sides of every edge the grammar has. Disagreements with libxml2 that are deliberate are
listed in KNOWN_DIFFERENCES with the reason and left out of the table. A mismatch prints its table and
index and exits 1.
"""
import pathlib
import random
from xml.sax.saxutils import escape

import lxml.etree as ET

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261022)
XS = 'http://www.w3.org/2001/XMLSchema'

TYPES = ['string', 'normalizedString', 'token', 'language', 'Name', 'NCName', 'NMTOKEN', 'ID', 'IDREF', 'anyURI', 'QName', 'boolean',
         'decimal', 'integer', 'nonPositiveInteger', 'negativeInteger', 'nonNegativeInteger', 'positiveInteger', 'long', 'int', 'short', 'byte',
         'unsignedLong', 'unsignedInt', 'unsignedShort', 'unsignedByte', 'float', 'double', 'duration', 'dateTime', 'time', 'date',
         'gYearMonth', 'gYear', 'gMonthDay', 'gDay', 'gMonth', 'hexBinary', 'base64Binary']
ENUM = {t: t[0].upper() + t[1:] for t in TYPES}
ENUM.update({'NMTOKEN': 'NMToken', 'IDREF': 'IDREF', 'ID': 'ID', 'anyURI': 'AnyURI', 'QName': 'QName', 'NCName': 'NCName', 'Name': 'Name'})

KNOWN_DIFFERENCES = {}

SEEDS = {
    'string': ['', 'a', ' a ', 'a\tb', 'a\nb', 'x y', '日本語', 'é', '\U0001F600'],
    'language': ['en', 'en-US', 'de-CH-1996', 'i-klingon', 'x-private', 'abcdefgh', 'abcdefghi', 'en-', '-en', 'en--US', '1a', 'a1', 'en-123456789', 'en-12345678'],
    'Name': ['a', ':a', 'a:b', '_x', 'a-b', 'a.b', '1a', '-a', '.a', 'a b', 'é', 'é1', '日本', 'a·', '·a', 'à', '̀a', ':', 'a:', '::', 'x ', 'a‌', '\U00010000', '\U000EFFFF', '\U000F0000', 'a×', 'a÷'],
    'anyURI': ['', 'http://example.org/a?b=c#d', 'a b', 'a%20b', 'a%2', 'a%zz', '%', 'a#b#c', '../x', 'urn:isbn:0451450523', 'a<b', 'a>b', 'a"b', 'a{b', 'a|b', 'a\\b', 'a^b', 'a`b', '日本', 'http://[::1]/', ':', '//host', 'a\tb'],
    'boolean': ['true', 'false', '1', '0', 'TRUE', 'True', 'yes', '', '2', '-1', ' true ', 'true false', '01', 'tru'],
    'decimal': ['0', '-0', '+0', '1.', '.1', '.', '', '+', '-', '1.5', '-1.5', '+1.5', '1e5', '1.5.2', '00012', '12345678901234567890.123456789', 'NaN', 'INF', '1,5', '١٢'],
    'integer': ['0', '-0', '+0', '1.0', '', '+', '-', '007', '-007', '123456789012345678901234567890', '1e3', '--1', '+-1', '1 2'],
    'float': ['0', '1', 'INF', '-INF', '+INF', 'NaN', 'nan', 'inf', 'INFINITY', '1e5', '1E5', '1e+5', '1e-5', '1e', 'e5', '.5e5', '5.e5', '.e5', '1.5', '+1.5', '1e5.5', '1ee5', '0x10', '1e999', '-1e999', '1e-999', '+', '', '1 e5', '1_0'],
    'duration': ['P1Y', 'P1M', 'P1D', 'PT1H', 'PT1M', 'PT1S', 'P', 'PT', '-P1Y', '+P1Y', 'P1Y2M3DT4H5M6S', 'P1Y2M3DT4H5M6.7S', 'P1.5Y', 'P1.5D', 'PT1.5H', 'PT1.5S', 'PT.5S', 'PT1.S', 'P1D1Y', 'P1M1Y', 'PT1S1M', 'P1YT', 'P0Y', 'P0D', 'P-1Y', 'PT0S', 'P1Y2M3DT', 'P1', 'PY', 'P1Y 2M', 'p1y', 'P1W', 'P0001Y', 'P99999999999Y'],
    'dateTime': ['2000-01-01T00:00:00', '2000-01-01T00:00:00Z', '2000-01-01T00:00:00.5', '2000-01-01T00:00:00.', '2000-01-01T24:00:00', '2000-01-01T24:00:00.0', '2000-01-01T24:00:01', '2000-01-01T23:59:59', '2000-01-01T23:60:00', '2000-01-01T23:59:60', '2000-02-29T00:00:00', '1900-02-29T00:00:00', '2100-02-29T00:00:00', '2000-02-30T00:00:00', '2001-04-31T00:00:00', '2000-13-01T00:00:00', '2000-00-01T00:00:00', '2000-01-00T00:00:00', '0000-01-01T00:00:00', '-0001-01-01T00:00:00', '-0001-02-29T00:00:00', '0001-01-01T00:00:00', '00001-01-01T00:00:00', '12345-01-01T00:00:00', '012345-01-01T00:00:00', '999-01-01T00:00:00', '2000-1-01T00:00:00', '2000-01-1T00:00:00', '2000-01-01t00:00:00', '2000-01-01 00:00:00', '2000-01-01T0:00:00', '2000-01-01T00:00', '2000-01-01T00:00:00+14:00', '2000-01-01T00:00:00+14:01', '2000-01-01T00:00:00-14:00', '2000-01-01T00:00:00+15:00', '2000-01-01T00:00:00+13:59', '2000-01-01T00:00:00+0100', '2000-01-01T00:00:00+01', '2000-01-01T00:00:00+01:60', '2000-01-01T00:00:00z', '2000-01-01T00:00:00ZZ', '2000-01-01T00:00:00.123456789012Z'],
    'time': ['00:00:00', '23:59:59', '24:00:00', '24:00:01', '24:01:00', '12:00:00.5', '12:00:00.', '12:60:00', '12:00:60', '1:00:00', '12:0:00', '12:00:0', '12:00', '12:00:00Z', '12:00:00+14:00', '12:00:00+14:01', '12:00:00-05:30', '12:00:00+5:30', '25:00:00', ' 12:00:00 ', '12:00:00.0000Z', '24:00:00.000'],
    'date': ['2000-01-01', '2000-02-29', '1900-02-29', '2000-02-30', '2000-01-01Z', '2000-01-01+01:00', '2000-01-01T00:00:00', '-2000-01-01', '0000-01-01', '2000-01', '2000-13-01', '2000-12-32', '20000101', '2000/01/01', '12345-12-31', '0123-01-01', '2000-1-1', '2000-01-01+14:00', '2000-01-01+14:30'],
    'gYearMonth': ['2000-01', '2000-12', '2000-13', '2000-00', '2000-1', '2000', '-2000-05', '0000-01', '12345-01', '2000-01Z', '2000-01+05:00', '2000-01-01', '999-01', '2000-01+15:00'],
    'gYear': ['2000', '-2000', '0000', '0001', '999', '12345', '012345', '2000Z', '2000+05:00', '2000-01', '20000', '-0001', '2000+14:00', '2000+14:01', 'abcd', ''],
    'gMonthDay': ['--01-01', '--12-31', '--02-29', '--02-30', '--04-31', '--13-01', '--00-01', '--01-00', '--1-01', '-01-01', '--01-01Z', '--01-01+05:00', '--0101', '01-01', '--01-1', '--01-32'],
    'gDay': ['---01', '---31', '---32', '---00', '---1', '--01', '---01Z', '---01+05:00', '---001', '01', '---1Z'],
    'gMonth': ['--01', '--12', '--13', '--00', '--1', '-01', '--01Z', '--01+05:00', '--01--', '--12--', '01', '--001'],
    'hexBinary': ['', '00', 'ff', 'FF', 'aB', 'abc', 'g0', '0 0', ' 00 ', '0x00', '00ff00ff', '0g', '0', '00\n'],
    'base64Binary': ['', 'QQ==', 'QQ=', 'QQ', 'QUI=', 'QUJD', 'QUJDRA==', 'QUJDRA=', 'QUJDRA', 'QR==', 'QQ=a', '=QQ=', 'QQ===', 'Q Q = =', 'QUJD\nRA==', 'QR==', 'QUJ=', 'QUK=', 'AAAA', 'AA==', 'AB==', 'AAB=', 'AAC=', '++//', '--__', 'QU JD', 'QUJD ', 'QUJ D', '*AAA', 'A==='],
}
SEEDS['normalizedString'] = SEEDS['string']
SEEDS['token'] = SEEDS['string']
SEEDS['NCName'] = SEEDS['Name']
SEEDS['NMTOKEN'] = SEEDS['Name']
SEEDS['ID'] = SEEDS['Name']
SEEDS['IDREF'] = SEEDS['Name']
SEEDS['QName'] = SEEDS['Name'] + ['a:b', 'a:b:c', ':a', 'a:', 'xml:lang', 'a: b']
for t in ('nonPositiveInteger', 'negativeInteger', 'nonNegativeInteger', 'positiveInteger'):
    SEEDS[t] = SEEDS['integer'] + ['-1', '1', '+1', '-00', '+00', '00', '-0', '-99999999999999999999999999999999999999999999999999999999', '99999999999999999999999999999999999999999999999999999999']
SEEDS['long'] = SEEDS['integer'] + ['9223372036854775807', '9223372036854775808', '-9223372036854775808', '-9223372036854775809', '09223372036854775807', '+9223372036854775807', '-0009223372036854775808']
SEEDS['int'] = SEEDS['integer'] + ['2147483647', '2147483648', '-2147483648', '-2147483649', '0002147483647', '+2147483647']
SEEDS['short'] = SEEDS['integer'] + ['32767', '32768', '-32768', '-32769', '0032767']
SEEDS['byte'] = SEEDS['integer'] + ['127', '128', '-128', '-129', '000127', '+127', '-0']
SEEDS['unsignedLong'] = SEEDS['integer'] + ['18446744073709551615', '18446744073709551616', '-1', '-0', '+18446744073709551615', '00018446744073709551615']
SEEDS['unsignedInt'] = SEEDS['integer'] + ['4294967295', '4294967296', '-1', '-0', '+4294967295']
SEEDS['unsignedShort'] = SEEDS['integer'] + ['65535', '65536', '-1', '-0']
SEEDS['unsignedByte'] = SEEDS['integer'] + ['255', '256', '-1', '-0', '+255']
SEEDS['double'] = SEEDS['float']

ALPHABETS = {
    'string': 'ab \t\n',
    'language': 'abAB19- ',
    'Name': 'ab:_-.1 é日·̀',
    'anyURI': 'ab:/%#?09 <>{}',
    'boolean': 'tru1e0 s',
    'numeric': '0123456789+-.eE INFa',
    'date': '0123456789-:TZ+.- ',
    'duration': 'PYMDTHS0123456789.-',
    'binary': 'AQgw0123456789abcdefABCDEF+/= \n',
}


def alphabet(t):
    if t in ('string', 'normalizedString', 'token'):
        return ALPHABETS['string']
    if t == 'language':
        return ALPHABETS['language']
    if t in ('Name', 'NCName', 'NMTOKEN', 'ID', 'IDREF', 'QName'):
        return ALPHABETS['Name']
    if t == 'anyURI':
        return ALPHABETS['anyURI']
    if t == 'boolean':
        return ALPHABETS['boolean']
    if t == 'duration':
        return ALPHABETS['duration']
    if t in ('dateTime', 'time', 'date', 'gYearMonth', 'gYear', 'gMonthDay', 'gDay', 'gMonth'):
        return ALPHABETS['date']
    if t in ('hexBinary', 'base64Binary'):
        return ALPHABETS['binary']
    return ALPHABETS['numeric']


def mutate(text, alpha):
    s = list(text)
    for _ in range(rnd.randint(1, 3)):
        op = rnd.randrange(4)
        if op == 0 and s:
            del s[rnd.randrange(len(s))]
        elif op == 1:
            s.insert(rnd.randrange(len(s) + 1), rnd.choice(alpha))
        elif op == 2 and s:
            s[rnd.randrange(len(s))] = rnd.choice(alpha)
        else:
            s = list(rnd.choice([' ', '\t', '\n']) + ''.join(s) + rnd.choice(['', ' ', '\n']))
    return ''.join(s)


NAME_TYPES = ('Name', 'NCName', 'NMTOKEN', 'ID', 'IDREF', 'QName')
DATE_TYPES = ('dateTime', 'time', 'date', 'gYearMonth', 'gYear', 'gMonthDay', 'gDay', 'gMonth')
BIG_TYPES = ('decimal', 'integer', 'nonPositiveInteger', 'negativeInteger', 'nonNegativeInteger', 'positiveInteger')


def skip(t, text):
    """Why libxml2's verdict is not the XSD verdict for this candidate, or None. Skipped candidates are
    covered by the hand-written SPEC table below with the verdict the Schema specification gives."""
    import re
    trimmed = text.strip(' \t\n')
    padded = trimmed != text
    digits = len(re.sub(r'\D', '', trimmed))
    if t == 'anyURI':
        return 'libxml2 runs a URI parser; the library accepts any string of XML characters'
    if t in NAME_TYPES and any(0x2000 <= ord(c) <= 0x2FFF or ord(c) >= 0x10000 for c in text):
        return 'libxml2 uses the XML 1.0 4th-edition name tables; the library uses the 5th'
    if t == 'QName' and ':' in text and not trimmed.startswith('xml:'):
        return 'libxml2 resolves the prefix against the instance document'
    if t in BIG_TYPES and digits > 18:
        return 'libxml2 limits decimal and integer values to about 18 digits'
    if t == 'decimal' and not re.search(r'\d', trimmed):
        return 'libxml2 accepts a bare sign after whitespace'
    if t.startswith('unsigned') and trimmed[:1] in ('+', '-'):
        return 'libxml2 refuses a sign on unsigned types; the lexical space allows one'
    if t in ('float', 'double'):
        if re.search(r'[eE][+-]?$', trimmed):
            return 'libxml2 accepts an exponent with no digits'
        if padded and ('INF' in text or 'NaN' in text):
            return 'libxml2 does not collapse whitespace around INF and NaN'
    if t == 'duration':
        if padded:
            return 'libxml2 does not collapse whitespace in durations'
        if re.search(r'T\.|\.S|\d{10}', trimmed):
            return 'libxml2 accepts a missing digit around the decimal point and overflows on long counts'
    if t in DATE_TYPES and padded:
        return 'libxml2 does not collapse whitespace in date and time types'
    if t == 'dateTime' and trimmed.startswith('-0001-02-29'):
        return 'leap-year rule for negative years differs (the library counts -0001 as astronomical year 0)'
    if t == 'base64Binary' and ('-' in text or '_' in text):
        return 'libxml2 accepts the URL-safe alphabet'
    return None


def libxml_verdicts(t, texts):
    schema = ET.XMLSchema(ET.fromstring('<xs:schema xmlns:xs="%s"><xs:element name="e" type="xs:%s"/></xs:schema>' % (XS, t)))
    out = []
    for text in texts:
        # escape markup and carriage returns; tab and newline pass through unchanged
        doc = '<e>%s</e>' % escape(text).replace('\r', '&#13;')
        out.append(bool(schema.validate(ET.fromstring(doc.encode('utf-8')))))
    return out


def quote(s):
    out = '"'
    for ch in s:
        if ch == '\\':
            out += '\\\\'
        elif ch == '"':
            out += '\\"'
        elif ch == '\n':
            out += '\\n'
        elif ch == '\t':
            out += '\\t'
        else:
            out += ch
    return out + '"'


DUMP = {}
lines = []
total = 0
valid_total = 0
for t in TYPES:
    seeds = list(dict.fromkeys(SEEDS.get(t, ['0', '1', 'a', ''])))
    pool = list(seeds)
    alpha = alphabet(t)
    attempts = 0
    while len(pool) < 130 and attempts < 4000:
        attempts += 1
        base = rnd.choice(seeds) if seeds else ''
        cand = mutate(base, alpha)
        if cand not in pool and '\r' not in cand:
            pool.append(cand)
    # whitespace variants of the first few valid seeds
    texts = [x for x in pool if '\x00' not in x]
    verdicts = libxml_verdicts(t, texts)
    texts_kept = [(x, v) for x, v in zip(texts, verdicts) if skip(t, x) is None]
    # make sure both verdicts are well represented
    if t == 'anyURI':
        continue  # every candidate is skipped (see skip()); the SPEC table covers it
    assert any(v for _, v in texts_kept) and (t in ('string', 'normalizedString', 'token') or any(not v for _, v in texts_kept)), t
    total += len(texts_kept)
    valid_total += sum(v for _, v in texts_kept)
    DUMP[t] = texts_kept
    name = t
    lines.append('    let t_%s = [%d]str{ %s }' % (name, len(texts_kept), ', '.join(quote(x) for x, _ in texts_kept)))
    lines.append('    let w_%s = [%d]bool{ %s }' % (name, len(texts_kept), ', '.join('true' if v else 'false' for _, v in texts_kept)))
    lines.append('    var i_%s = 0usize' % name)
    lines.append('    while i_%s < %d {' % (name, len(texts_kept)))
    lines.append('        if xsd.valid(.%s, t_%s[i_%s]) != w_%s[i_%s] { try report("%s", i_%s) }' % (ENUM[t], name, name, name, name, name, name))
    lines.append('        i_%s += 1usize' % name)
    lines.append('    }')

# The Schema specification's verdict where libxml2 differs (see skip()), written by hand.
SPEC = [
    ('unsignedByte', '+255', True), ('unsignedByte', '-0', True), ('unsignedByte', '+256', False), ('unsignedLong', '+0', True), ('unsignedLong', '+18446744073709551615', True),
    ('unsignedInt', '-0', True), ('unsignedInt', ' +7 ', True), ('unsignedShort', '+1', True), ('unsignedShort', '-1', False),
    ('integer', '1234567890123456789012345678901234567890', True), ('integer', '-1234567890123456789012345678901234567890', True),
    ('decimal', '12345678901234567890.123456789012345678', True), ('decimal', ' - ', False), ('decimal', '+', False),
    ('nonNegativeInteger', '99999999999999999999999999999999999999999999999999999999', True), ('nonNegativeInteger', '-99999999999999999999999999999999999999999999999999999999', False),
    ('positiveInteger', '123456789012345678901234567890', True), ('positiveInteger', '0', False), ('positiveInteger', '-0', False),
    ('negativeInteger', '-99999999999999999999999999999999999999999999999999999999', True), ('negativeInteger', '-0', False), ('negativeInteger', '99999999999999999999999999999', False),
    ('nonPositiveInteger', '-99999999999999999999999999999999999999999999999999999999', True), ('nonPositiveInteger', '0', True), ('nonPositiveInteger', '+0', True), ('nonPositiveInteger', '1', False),
    ('float', '1e', False), ('float', '1e+', False), ('double', '1e-', False), ('double', '.5e', False), ('float', ' INF ', True), ('double', '\nNaN\n', True), ('float', ' -INF', True), ('float', '+INF', False),
    ('duration', 'PT.5S', False), ('duration', 'PT1.S', False), ('duration', ' PT1S ', True), ('duration', '\tP1Y\n', True), ('duration', 'P99999999999Y', True), ('duration', 'PT0.5S', True),
    ('date', ' 2000-01-01 ', True), ('date', '\t2000-02-29\n', True), ('time', ' 12:00:00 ', True), ('time', '\t24:00:00\n', True), ('dateTime', ' 2000-01-01T00:00:00 ', True),
    ('dateTime', '\n2000-01-01T00:00:00-14:00\n', True), ('gYear', ' 2000 ', True), ('gYearMonth', '\n2000-01+05:00\n', True), ('gMonthDay', ' --01-01Z ', True), ('gDay', ' ---01 ', True), ('gMonth', '\t--01\n', True),
    ('dateTime', '-0001-02-29T00:00:00', True), ('dateTime', '-0002-02-29T00:00:00', False), ('dateTime', '-0004-02-29T00:00:00', False), ('dateTime', '-0005-02-29T00:00:00', True), ('dateTime', '0000-01-01T00:00:00', False),
    ('Name', 'a\u200c', True), ('Name', '\U00010000', True), ('Name', '\U000EFFFF', True), ('Name', '\U000F0000', False), ('Name', 'a\u2000', False), ('Name', '\u200c', True), ('Name', 'a\u00b7', True),
    ('NMTOKEN', '\u200c', True), ('NMTOKEN', 'a b', False), ('NMTOKEN', '', False), ('NMTOKEN', '\U00010000', True), ('NCName', 'a\u200d', True), ('NCName', 'a:b', False), ('NCName', '\u0300', False),
    ('ID', '\U0001D7CE', True), ('IDREF', 'x\u200c', True), ('QName', 'a:b', True), ('QName', 'a:b:c', False), ('QName', ':a', False), ('QName', 'a:', False), ('QName', 'x:\u200c', True), ('QName', ' a:b ', True),
    ('anyURI', '', True), ('anyURI', 'a b', True), ('anyURI', 'http://[::1/', True), ('anyURI', ':', True), ('anyURI', 'a%zz', True), ('anyURI', '\u65e5\u672c', True), ('anyURI', ' \t x \n', True),
    ('base64Binary', '--__', False), ('base64Binary', 'QUJD', True), ('base64Binary', 'QUJ-', False),
]
lines.append('    let spec_types = [%d]xsd.Type{ %s }' % (len(SPEC), ', '.join('.' + ENUM[x[0]] for x in SPEC)))
lines.append('    let spec_texts = [%d]str{ %s }' % (len(SPEC), ', '.join(quote(x[1]) for x in SPEC)))
lines.append('    let spec_want = [%d]bool{ %s }' % (len(SPEC), ', '.join('true' if x[2] else 'false' for x in SPEC)))
lines.append('    var spec_i = 0usize')
lines.append('    while spec_i < %d {' % len(SPEC))
lines.append('        if xsd.valid(spec_types[spec_i], spec_texts[spec_i]) != spec_want[spec_i] { try report("spec", spec_i) }')
lines.append('        spec_i += 1usize')
lines.append('    }')

# type_named and whitespace
lines.append('    var named = 0usize')
for t in TYPES:
    lines.append('    let (n_%s, f_%s) = xsd.type_named("%s")' % (t, t, t))
    lines.append('    if !f_%s || n_%s != .%s { try report("type-named", named) }' % (t, t, ENUM[t]))
    lines.append('    named += 1usize')
for k, bad in enumerate(('', 'String', 'INT', 'xs:int', 'int ', 'anySimpleType', 'dateTimeStamp', 'Boolean', 'integers')):
    lines.append('    let (_, found_%d) = xsd.type_named(%s)' % (k, quote(bad)))
    lines.append('    if found_%d { try report("type-named-unknown", %dusize) }' % (k, k))
lines.append('    if xsd.whitespace(.String) != xsd.Whitespace.Preserve || xsd.whitespace(.NormalizedString) != xsd.Whitespace.Replace || xsd.whitespace(.Token) != xsd.Whitespace.Collapse || xsd.whitespace(.Int) != xsd.Whitespace.Collapse || xsd.whitespace(.Base64Binary) != xsd.Whitespace.Collapse { try report("whitespace", 0usize) }')

body = '\n'.join(lines)
source = '''// e.fmt.xsd.valid against libxml2's schema validator through lxml (L081, D2271 part 1; scripts/
// xsd_datatype_reference.py writes this file): for each of the 39 built-in types, boundary and seeded-
// mutation candidates (padding, inserted, deleted and replaced characters, non-ASCII name characters)
// with the verdict libxml2 gives for `<e>text</e>` under `<xs:element name="e" type="xs:T"/>`. A mismatch
// prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.fmt.xsd

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
    try io.print("xsd mismatch in ")
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
    try io.print("fmt xsd types ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_xsd_types' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote fmt_xsd_types: %d cases (%d valid) over %d types; libxml2 %s' % (total, valid_total, len(TYPES), '.'.join(map(str, ET.LIBXML_VERSION))))

import json, os
if os.environ.get('XSD_DUMP'):
    json.dump({k: v for k, v in DUMP.items()}, open(os.environ['XSD_DUMP'], 'w', encoding='utf-8'), ensure_ascii=False)
