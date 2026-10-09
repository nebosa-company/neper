"""Write tests/selfhost/fixtures/link/fmt_xpath/src/main.e (L081, D2273: the XPath 1.0 engine).

  python scripts/xpath_reference.py

e.fmt.xpath against libxml2's XPath through lxml. Four sample documents (attributes, text, mixed content,
comments, processing instructions, namespaces, numbers and strings that exercise the conversions) and about
3,000 seeded expressions generated from the XPath 1.0 grammar: location paths over every axis the engine
implements with name, wildcard, prefix and node-type tests and predicates (numeric, boolean, nested), unions,
filter expressions, all four result types, every operator, and every core function. The expected result is
libxml2's, rendered the same way on both sides: a node-set as the node kind, name and string-value of each
node in order, a number as a double (NaN and the infinities included), a string verbatim, a boolean. A
mismatch prints its table and index and exits 1.
"""
import math
import pathlib
import random

import lxml.etree as ET

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261024)
NS = {'p': 'urn:p', 'q': 'urn:q'}

DOCS = [
    '<r><a x="1" y="u">one</a><a x="2">two</a><b><a x="3" y="v">three<c/>tail</a><c>4</c><c>5.5</c></b><!-- note --><?pi data?><d>  spaced   out  </d><e/></r>',
    '<lib xmlns:p="urn:p"><p:book id="b1" year="1999"><p:title>First</p:title><p:price>10</p:price></p:book><p:book id="b2" year="2005"><p:title>Second</p:title><p:price>25.5</p:price></p:book><p:book id="b3"><p:title>Third</p:title><p:price>-3</p:price></p:book><note>plain</note></lib>',
    '<t><s n="1">alpha</s><s n="2">beta</s><s n="3">gamma</s><s n="10">delta</s><g><s n="5">x</s><s n="6">y</s></g><u v="a b"> a  b </u><z>1e3</z><z>0x10</z><z></z><z>NaN</z><z>-0</z></t>',
    '<m>text <i>italic</i> more <b>bold <i>both</i></b> end<![CDATA[ <cdata> ]]><?target some data?><!--c1--><n a="1" b="2" c="3"/><n a="3" b="2" c="1"/></m>',
]
NAMES = ['a', 'b', 'c', 'd', 'e', 'r', 'p:book', 'p:title', 'p:price', 'note', 's', 'g', 'u', 'z', 'i', 'n', 'm', 't', 'lib', 'x', 'y', 'id', 'year', 'n', 'v', 'a', 'b', 'c']
AXES = ['child', 'descendant', 'parent', 'ancestor', 'following-sibling', 'preceding-sibling', 'following', 'preceding', 'attribute', 'self', 'descendant-or-self', 'ancestor-or-self']
LITERALS = ['one', 'two', 'x', 'First', '1', '2', '3', '10', '5.5', 'a b', '', 'b1', 'alpha', '4']
NUMS = ['0', '1', '2', '3', '10', '0.5', '-1', '2.5', '100', '3.14159', '1000000', '0.001', '-0.5', '7']
STRFUNCS = ['string', 'normalize-space', 'local-name', 'name', 'namespace-uri']


def pick(seq):
    return rnd.choice(seq)


def gen_step():
    axis = pick(AXES)
    r = rnd.random()
    if r < 0.50:
        test = pick(NAMES)
    elif r < 0.62:
        test = '*'
    elif r < 0.66:
        test = 'p:*'
    elif r < 0.76:
        test = 'node()'
    elif r < 0.84:
        test = 'text()'
    elif r < 0.88:
        test = 'comment()'
    elif r < 0.92:
        test = 'processing-instruction()'
    else:
        test = pick(NAMES)
    if axis == 'attribute' and test in ('text()', 'comment()', 'processing-instruction()'):
        test = pick(['x', 'y', 'id', '*', 'node()'])
    preds = ''
    for _ in range(rnd.choice([0, 0, 0, 1, 1, 2])):
        preds += '[%s]' % gen_pred()
    if rnd.random() < 0.15 and axis == 'child':
        return test + preds  # abbreviated
    return '%s::%s%s' % (axis, test, preds)


def gen_pred():
    r = rnd.random()
    if r < 0.2:
        return str(rnd.randint(1, 4))
    if r < 0.3:
        return 'last()'
    if r < 0.4:
        return 'position() %s %d' % (pick(['=', '<', '>', '<=', '>=', '!=']), rnd.randint(1, 4))
    if r < 0.5:
        return '@%s' % pick(['x', 'y', 'id', 'n', 'a'])
    if r < 0.6:
        return '@%s %s %s' % (pick(['x', 'y', 'id', 'n', 'year', 'a']), pick(['=', '!=', '<', '>']), pick(['1', '2', "'1'", "'b1'", "'u'", '3']))
    if r < 0.7:
        return gen_bool(2)
    if r < 0.8:
        return pick(NAMES)
    if r < 0.9:
        return '%s %s %s' % (gen_num(1), pick(['=', '<', '>', '<=']), gen_num(1))
    return 'not(%s)' % pick(['@x', 'a', 'b', 'c', '*', 'text()'])


def gen_path(depth=2):
    r = rnd.random()
    parts = []
    n = rnd.randint(1, 3)
    prefix = ''
    if r < 0.3:
        prefix = '/'
    elif r < 0.4:
        prefix = '//'
    elif r < 0.45:
        prefix = './/'
    elif r < 0.5:
        prefix = '../'
    for _ in range(n):
        parts.append(gen_step())
    return prefix + '/'.join(parts)


def gen_nodeset(depth):
    r = rnd.random()
    if depth <= 0 or r < 0.55:
        return gen_path()
    if r < 0.7:
        return '(%s | %s)' % (gen_nodeset(depth - 1), gen_nodeset(depth - 1))
    if r < 0.8:
        return '(%s)[%d]' % (gen_nodeset(depth - 1), rnd.randint(1, 3))
    if r < 0.85:
        return '(%s)[%s]' % (gen_nodeset(depth - 1), gen_pred())
    if r < 0.9:
        return '(%s)/%s' % (gen_nodeset(depth - 1), gen_step())
    return '.'


def gen_str(depth):
    r = rnd.random()
    if depth <= 0 or r < 0.25:
        return "'%s'" % pick(LITERALS)
    if r < 0.4:
        return 'string(%s)' % gen_nodeset(depth - 1)
    if r < 0.5:
        return 'concat(%s, %s)' % (gen_str(depth - 1), gen_str(depth - 1))
    if r < 0.6:
        return 'substring(%s, %s)' % (gen_str(depth - 1), gen_num(depth - 1))
    if r < 0.66:
        return 'substring(%s, %s, %s)' % (gen_str(depth - 1), gen_num(depth - 1), gen_num(depth - 1))
    if r < 0.72:
        return '%s(%s)' % (pick(['substring-before', 'substring-after']), ', '.join([gen_str(depth - 1), gen_str(depth - 1)]))
    if r < 0.78:
        return 'translate(%s, %s, %s)' % (gen_str(depth - 1), pick(["'abc'", "'lo'", "'ae'", "''"]), pick(["'ABC'", "'01'", "''", "'xyz'"]))
    if r < 0.85:
        return 'normalize-space(%s)' % gen_str(depth - 1)
    if r < 0.9:
        return '%s(%s)' % (pick(['local-name', 'name', 'namespace-uri']), gen_nodeset(depth - 1))
    if r < 0.94:
        return 'string(%s)' % gen_num(depth - 1)
    return 'string(%s)' % gen_bool(depth - 1)


def gen_num(depth):
    r = rnd.random()
    if depth <= 0 or r < 0.25:
        return pick(NUMS)
    if r < 0.4:
        return 'count(%s)' % gen_nodeset(depth - 1)
    if r < 0.5:
        return 'string-length(%s)' % gen_str(depth - 1)
    if r < 0.58:
        return 'sum(%s)' % gen_nodeset(depth - 1)
    if r < 0.64:
        return 'number(%s)' % gen_str(depth - 1)
    if r < 0.7:
        return '%s(%s)' % (pick(['floor', 'ceiling', 'round']), gen_num(depth - 1))
    if r < 0.9:
        return '(%s %s %s)' % (gen_num(depth - 1), pick(['+', '-', '*', 'div', 'mod']), gen_num(depth - 1))
    if r < 0.95:
        return '-%s' % gen_num(depth - 1)
    return 'number(%s)' % gen_nodeset(depth - 1)


def gen_bool(depth):
    r = rnd.random()
    if depth <= 0 or r < 0.15:
        return pick(['true()', 'false()'])
    if r < 0.4:
        return '%s %s %s' % (gen_value(depth - 1), pick(['=', '!=', '<', '<=', '>', '>=']), gen_value(depth - 1))
    if r < 0.5:
        return 'boolean(%s)' % gen_value(depth - 1)
    if r < 0.6:
        return 'not(%s)' % gen_bool(depth - 1)
    if r < 0.7:
        return '(%s %s %s)' % (gen_bool(depth - 1), pick(['and', 'or']), gen_bool(depth - 1))
    if r < 0.78:
        return '%s(%s, %s)' % (pick(['starts-with', 'contains']), gen_str(depth - 1), gen_str(depth - 1))
    if r < 0.82:
        return 'lang(%s)' % pick(["'en'", "'x'"])
    return gen_nodeset(depth - 1)


def gen_value(depth):
    r = rnd.random()
    if r < 0.35:
        return gen_nodeset(depth)
    if r < 0.6:
        return gen_str(depth)
    if r < 0.85:
        return gen_num(depth)
    return gen_bool(depth)


def gen_expr():
    r = rnd.random()
    if r < 0.4:
        return gen_nodeset(2)
    if r < 0.6:
        return gen_str(3)
    if r < 0.85:
        return gen_num(3)
    return gen_bool(3)


def describe_node(item):
    if isinstance(item, str):
        if getattr(item, 'is_attribute', False):
            return 'A:%s:%s' % (item.attrname.split('}')[-1], str(item))
        return 'T:%s' % str(item)
    tag = item.tag
    if tag is ET.Comment:
        return 'C:%s' % item.text
    if tag is ET.ProcessingInstruction:
        return 'P:%s:%s' % (item.target, item.text or '')
    local = tag.split('}')[-1]
    return 'E:%s:%s' % (local, item.xpath('string(.)'))


SEP = '¦'


def render(result):
    if isinstance(result, bool):
        return 'B', 'true' if result else 'false'
    if isinstance(result, float):
        if math.isnan(result):
            return 'N', 'NaN'
        if math.isinf(result):
            return 'N', 'Infinity' if result > 0 else '-Infinity'
        return 'N', repr(result)
    if isinstance(result, str):
        return 'S', str(result)
    if isinstance(result, list):
        return 'L', SEP.join(describe_node(i) for i in result)
    raise TypeError(type(result))


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
        elif ch == '\r':
            out += '\\r'
        else:
            out += ch
    return out + '"'


trees = [ET.fromstring(d.encode('utf-8')) for d in DOCS]
cases = []
seen = set()
attempts = 0
while len(cases) < 3000 and attempts < 40000:
    attempts += 1
    expr = gen_expr()
    di = rnd.randrange(len(DOCS))
    if (di, expr) in seen:
        continue
    seen.add((di, expr))
    try:
        result = trees[di].xpath(expr, namespaces=NS)
        kind, text = render(result)
    except (ET.XPathError, TypeError):
        continue
    # a node-set that holds a namespace node or a tail string is not what this fixture compares
    if kind == 'L' and ('T:' in text and any(isinstance(i, str) and getattr(i, 'is_tail', False) for i in result)):
        continue
    import re
    if kind == 'S' and re.search(r'\d{15,}', text):
        continue  # libxml2 prints numbers with 15 significant digits; the specification asks for the shortest unique form
    cases.append((di, expr, kind, text))

# number formatting by the specification (the shortest decimal that identifies the double, never an exponent),
# checked through string(); and string-to-number conversions, which libxml2 gets right
from decimal import Decimal

for _ in range(260):
    mant = rnd.randint(1, 10 ** rnd.randint(1, 17) - 1)
    exp = rnd.randint(-28, 28)
    x = float('%de%d' % (mant, exp))
    if x == 0.0 or math.isinf(x):
        continue
    plain = format(Decimal(repr(x)), 'f')
    if '.' in plain:
        plain = plain.rstrip('0').rstrip('.')
    cases.append((0, 'string(%s)' % format(Decimal(repr(x)), 'f'), 'S', plain))
for lit in ['0.1', '0.2', '0.30000000000000004', '1', '100', '1000000000000000000000', '0.0000001', '123456789012345678', '4.9e-324', '1.7976931348623157e308']:
    x = float(lit)
    plain = format(Decimal(repr(x)), 'f')
    if '.' in plain:
        plain = plain.rstrip('0').rstrip('.')
    cases.append((0, 'string(%s)' % format(Decimal(repr(x)), 'f'), 'S', plain))
cases.append((0, 'string(0.1 + 0.2)', 'S', '0.30000000000000004'))
cases.append((0, 'string(1 div 3)', 'S', '0.3333333333333333'))
cases.append((0, 'string(2 div 3)', 'S', '0.6666666666666666'))
cases.append((0, 'string(-0)', 'S', '0'))
cases.append((0, 'string(0 div 0)', 'S', 'NaN'))
cases.append((0, 'string(1 div 0)', 'S', 'Infinity'))
cases.append((0, 'string(-1 div 0)', 'S', '-Infinity'))
for text in ['12', '12.5', ' 12 ', '-12', '+12', '.5', '5.', '-.5', '- 5', '1 2', '', '0x10', 'Infinity', 'NaN', '--1', '1.2.3', '\t7\n', '00012', '-0', '1,5', '.', '-', 'abc', '3 ']:
    expr = 'number(%s)' % ("'" + text + "'")
    result = trees[0].xpath(expr, namespaces=NS)
    kind, rendered = render(result)
    cases.append((0, expr, kind, rendered))

cases.append((0, "number('1e3')", 'N', 'NaN'))  # libxml2 accepts an exponent here; the XPath 1.0 grammar has none
counts = {}
for c in cases:
    counts[c[2]] = counts.get(c[2], 0) + 1

lines = []
lines.append('    let docs = [%d]str{ %s }' % (len(DOCS), ', '.join(quote(d) for d in DOCS)))
CH = 250
for start in range(0, len(cases), CH):
    chunk = cases[start:start + CH]
    k = start // CH
    lines.append('    let x%d_doc = [%d]usize{ %s }' % (k, len(chunk), ', '.join('%dusize' % c[0] for c in chunk)))
    lines.append('    let x%d_expr = [%d]str{ %s }' % (k, len(chunk), ', '.join(quote(c[1]) for c in chunk)))
    lines.append('    let x%d_kind = [%d]str{ %s }' % (k, len(chunk), ', '.join(quote(c[2]) for c in chunk)))
    lines.append('    let x%d_want = [%d]str{ %s }' % (k, len(chunk), ', '.join(quote(c[3]) for c in chunk)))
    lines.append('    var x%d_i = 0usize' % k)
    lines.append('    while x%d_i < %d {' % (k, len(chunk)))
    lines.append('        if !agrees(a, &parsed[x%d_doc[x%d_i]], x%d_expr[x%d_i], x%d_kind[x%d_i], x%d_want[x%d_i]) { try report("x%d", x%d_i) }' % ((k,) * 10))
    lines.append('        x%d_i += 1usize' % k)
    lines.append('    }')
body = '\n'.join(lines)
source = '''// e.fmt.xpath against libxml2's XPath through lxml (L081, D2273; scripts/xpath_reference.py writes this
// file): %d seeded expressions over %d sample documents, the result of each compared in the form libxml2
// gives it (a node-set as node kind, name and string-value in order, a number as a double, a string, a
// boolean). A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.str
use e.fmt.xml as xml
use e.fmt.xpath as xp

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

// One node as the reference describes it: kind, name and string-value.
fn describe(a: *mem.Arena, d: *const xml.Document, n: xp.XNode) -> (str, err) {
    let node = d.nodes[usize(n.id)]
    let (text, text_error) = xp.string_of(a, d, n)
    if text_error != ok { ret ("", text_error) }
    var head = "T:"
    if n.attribute != 0u32 {
        let (_, local) = xp.expanded_name(d, n)
        let (h, h_error) = str.concat(a, "A:", local)
        if h_error != ok { ret ("", h_error) }
        let (h2, h2_error) = str.concat(a, h, ":")
        if h2_error != ok { ret ("", h2_error) }
        head = h2
    } else if node.kind == .Element {
        let (_, local) = xp.expanded_name(d, n)
        let (h, h_error) = str.concat(a, "E:", local)
        if h_error != ok { ret ("", h_error) }
        let (h2, h2_error) = str.concat(a, h, ":")
        if h2_error != ok { ret ("", h2_error) }
        head = h2
    } else if node.kind == .Comment {
        head = "C:"
    } else if node.kind == .Processing {
        let (h, h_error) = str.concat(a, "P:", node.name)
        if h_error != ok { ret ("", h_error) }
        let (h2, h2_error) = str.concat(a, h, ":")
        if h2_error != ok { ret ("", h2_error) }
        head = h2
    }
    let (whole, whole_error) = str.concat(a, head, text)
    ret (whole, whole_error)
}

fn agrees(a: *mem.Arena, d: *const xml.Document, expr: str, kind: str, want: str) -> bool {
    let checkpoint = mem.mark(a)
    let bindings = [2]xp.Binding{ xp.Binding { prefix: "p", uri: "urn:p" }, xp.Binding { prefix: "q", uri: "urn:q" } }
    let (v, v_error) = xp.run(a, d, expr, bindings[..])
    if v_error != ok {
        mem.reset(a, checkpoint)
        ret false
    }
    var good = false
    if same(kind, "B") {
        good = v.kind == xp.Kind.Boolean && v.flag == same(want, "true")
    } else if same(kind, "N") {
        if v.kind == xp.Kind.Number {
            if same(want, "NaN") {
                good = v.number != v.number
            } else if same(want, "Infinity") {
                good = v.number == xp.infinity()
            } else if same(want, "-Infinity") {
                good = v.number == -xp.infinity()
            } else {
                let (expected, parse_error) = str.parse_f64(want)
                good = parse_error == ok && abs64(v.number - expected) <= 1e-12f64 * (1.0f64 + abs64(expected))
            }
        }
    } else if same(kind, "S") {
        good = v.kind == xp.Kind.String && same(v.text, want)
    } else {
        if v.kind == xp.Kind.NodeSet {
            let sep = "@@SEP@@"
            var parts: [256]str = zero
            if v.nodes.len <= 256usize {
                // the reference cannot show the document node, so it is left out of both sides
                var i = 0usize
                var used = 0usize
                var failed = false
                while i < v.nodes.len && !failed {
                    if !(v.nodes[i].id == 0u32 && v.nodes[i].attribute == 0u32) {
                        let (one, one_error) = describe(a, d, v.nodes[i])
                        if one_error != ok { failed = true } else {
                            parts[used] = one
                            used += 1usize
                        }
                    }
                    i += 1usize
                }
                if !failed {
                    let (joined, join_error) = str.join(a, parts[..used], sep)
                    good = join_error == ok && same(joined, want)
                }
            }
        }
    }
    mem.reset(a, checkpoint)
    ret good
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
        digits[count] = u8(n %% 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("xpath mismatch in ")
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
@@DOCS@@
    var parsed: [%d]xml.Document = zero
    var pi = 0usize
    while pi < %d {
        let (doc, doc_error) = xml.parse(a, docs[pi])
        if doc_error != ok { try report("parse", pi) }
        parsed[pi] = doc
        pi += 1usize
    }
@@BODY@@
    try io.print("fmt xpath ok\\n")
    ret ok
}
''' % (len(cases), len(DOCS), len(DOCS), len(DOCS))
# expressions that must be refused: at compile time, or at evaluation time
COMPILE_ERRORS = ['', '1 +', 'a[', 'a/', '//', 'foo(', '@', '1 2', 'a b', 'child::', 'unknown::a', "'unterminated", 'a[1', '(1', '1)', '/ /', 'a//', '!', '1 ! 2', 'a:', '$', 'a[]', ':a', 'a::b::c', '..a', '.a']
EVAL_ERRORS = [('$undefined', 'UnknownVariable'), ('nosuchfunction()', 'UnknownFunction'), ('count()', 'WrongArity'), ('count(1)', 'TypeMismatch'), ('1 | 2', 'TypeMismatch'),
               ("sum('a')", 'TypeMismatch'), ('concat(1)', 'WrongArity'), ('substring(1)', 'WrongArity'), ('not()', 'WrongArity'), ('true(1)', 'WrongArity'), ('(1)[1]', 'TypeMismatch'), ('string(1, 2)', 'WrongArity')]
lines.append('    var errors_at = 0usize')
for k, text in enumerate(COMPILE_ERRORS):
    lines.append('    let (_, compile_error_%d) = xp.compile(a, %s, zero)' % (k, quote(text)))
    lines.append('    if compile_error_%d == ok { try report("compile-refusal", %dusize) }' % (k, k))
for k, (text, code) in enumerate(EVAL_ERRORS):
    lines.append('    let (_, eval_error_%d) = xp.run(a, &parsed[0usize], %s, zero)' % (k, quote(text)))
    lines.append('    if eval_error_%d != xp.%s { try report("eval-refusal", %dusize) }' % (k, code, k))
lines.append('    let (_, var_error) = xp.run(a, &parsed[0usize], "1 + 1", zero)')
lines.append('    if var_error != ok { try report("plain", 0usize) }')
# a bound variable and the current() extension
lines.append('    var bound = [2]xp.Variable{ xp.Variable { name: "n", value: xp.number_value(3.0) }, xp.Variable { name: "s", value: xp.string_value("two") } }')
lines.append('    let vars = xp.Variables { items: bound[..], count: 2usize }')
lines.append('    let (var_expr, var_expr_error) = xp.compile(a, "$n + count(//a[. = $s])", zero)')
lines.append('    if var_expr_error != ok { try report("variable-compile", 0usize) }')
lines.append('    let none = xp.no_extensions()')
lines.append('    let no_vars = xp.no_variables()')
lines.append('    let (var_value, var_value_error) = xp.evaluate(a, &var_expr, &parsed[0usize], xp.Context { node: xp.XNode { id: parsed[0usize].root, attribute: 0u32 }, position: 1usize, size: 1usize }, &vars, &none)')
lines.append('    if var_value_error != ok || var_value.kind != xp.Kind.Number || var_value.number != 4.0 { try report("variable-value", 0usize) }')
lines.append('    let current_node = xp.XNode { id: 2u32, attribute: 0u32 }')
lines.append('    let with_current = xp.Extensions { current: current_node, has_current: true }')
lines.append('    let (current_expr, current_expr_error) = xp.compile(a, "name(current())", zero)')
lines.append('    if current_expr_error != ok { try report("current-compile", 0usize) }')
lines.append('    let (current_value, current_value_error) = xp.evaluate(a, &current_expr, &parsed[0usize], xp.Context { node: xp.XNode { id: parsed[0usize].root, attribute: 0u32 }, position: 1usize, size: 1usize }, &no_vars, &with_current)')
lines.append('    if current_value_error != ok || current_value.kind != xp.Kind.String || !same(current_value.text, "a") { try report("current-value", 0usize) }')
lines.append('    let (no_current, no_current_error) = xp.run(a, &parsed[0usize], "current()", zero)')
lines.append('    if no_current_error != xp.UnknownFunction { try report("current-absent", 0usize) }')
doc_line = lines[0]
body = '\n'.join(lines[1:])
source = source.replace('@@DOCS@@', doc_line).replace('@@BODY@@', body).replace('@@SEP@@', SEP)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_xpath' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote fmt_xpath: %d cases %s' % (len(cases), counts))
import json
import os

if os.environ.get('XP_DUMP'):
    json.dump(cases, open(os.environ['XP_DUMP'], 'w', encoding='utf-8'), ensure_ascii=False)
