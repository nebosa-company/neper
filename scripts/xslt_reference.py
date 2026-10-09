"""Write tests/selfhost/fixtures/link/fmt_xslt/src/main.e (L081, D2274: the XSLT 1.0 core).

  python scripts/xslt_reference.py

e.fmt.xslt against libxslt through lxml. About fifty stylesheets cover the instructions the module implements
(identity copy, the built-in rules, templates with modes, priorities, unions and every pattern shape, apply-templates
and for-each with sort, call-template recursion and parameters, variables and result tree fragments, if and choose,
element, attribute, comment and processing-instruction constructors, attribute value templates, copy and copy-of,
literal result elements with namespaces, text output) and each is applied to handcrafted documents and seeded
random trees. libxslt's result is canonicalised (C14N, comments kept) and the library's output is parsed and
canonicalised by a canonicaliser written in the fixture, so serialisation differences that mean nothing do not
count; a text-method result is compared verbatim. A mismatch prints its table and index and exits 1.
"""
import io
import pathlib
import random

import lxml.etree as ET

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261025)
XSL = 'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"'


def sheet(body, method='xml', extra=''):
    out = '<xsl:output method="%s"%s/>' % (method, ' omit-xml-declaration="yes"' if method == 'xml' else '')
    return '<xsl:stylesheet version="1.0" %s %s>%s%s</xsl:stylesheet>' % (XSL, extra, out, body)


S = []


def add(name, body, method='xml', extra=''):
    S.append((name, sheet(body, method, extra), method))


add('identity', '<xsl:template match="@*|node()"><xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy></xsl:template>')
add('builtin-text', '', 'text')
add('builtin-wrap', '<xsl:template match="/"><out><xsl:apply-templates/></out></xsl:template>')
add('foreach-sort', '<xsl:template match="/"><out><xsl:for-each select="//*[@x]"><xsl:sort select="@x" data-type="number" order="descending"/><i x="{@x}" n="{position()}/{last()}"><xsl:value-of select="name()"/></i></xsl:for-each></out></xsl:template>')
add('foreach-sort-text', '<xsl:template match="/"><out><xsl:for-each select="//*[not(*)]"><xsl:sort select="."/><xsl:sort select="name()" order="descending"/><t><xsl:value-of select="."/></t></xsl:for-each></out></xsl:template>')
add('modes', '<xsl:template match="/"><o><xsl:apply-templates select="*" mode="a"/><xsl:apply-templates select="*" mode="b"/></o></xsl:template>'
    '<xsl:template match="*" mode="a"><A n="{name()}"/></xsl:template><xsl:template match="*" mode="b"><B><xsl:apply-templates select="*" mode="b"/></B></xsl:template>')
add('priorities', '<xsl:template match="/"><o><xsl:apply-templates select="//*[position() &lt; 6]"/></o></xsl:template>'
    '<xsl:template match="*">star</xsl:template><xsl:template match="a">a</xsl:template><xsl:template match="a[@x]">ax</xsl:template>'
    '<xsl:template match="b" priority="5">B5</xsl:template><xsl:template match="b|c">bc</xsl:template><xsl:template match="text()"/>')
add('patterns', '<xsl:template match="/"><o><xsl:apply-templates select="//node()"/></o></xsl:template>'
    '<xsl:template match="a/b">[a/b]</xsl:template><xsl:template match="b[1]">[b1]</xsl:template><xsl:template match="@*">[@]</xsl:template>'
    '<xsl:template match="text()[normalize-space()]">[t]</xsl:template><xsl:template match="comment()">[c]</xsl:template>'
    '<xsl:template match="processing-instruction()">[pi]</xsl:template><xsl:template match="/*/*">[top]</xsl:template>')
add('descendant-pattern', '<xsl:template match="/"><o><xsl:apply-templates select="//*"/></o></xsl:template><xsl:template match="r//c">[r//c]</xsl:template><xsl:template match="*"/>')
add('factorial', '<xsl:template match="/"><o><xsl:call-template name="fact"><xsl:with-param name="n" select="count(//*) mod 9 + 1"/></xsl:call-template></o></xsl:template>'
    '<xsl:template name="fact"><xsl:param name="n" select="1"/><xsl:param name="acc" select="1"/><xsl:choose><xsl:when test="$n &lt;= 1"><xsl:value-of select="$acc"/></xsl:when>'
    '<xsl:otherwise><xsl:call-template name="fact"><xsl:with-param name="n" select="$n - 1"/><xsl:with-param name="acc" select="$acc * $n"/></xsl:call-template></xsl:otherwise></xsl:choose></xsl:template>', 'xml')
add('variables', '<xsl:variable name="g" select="count(//*)"/><xsl:variable name="s" select="\'k\'"/><xsl:template match="/"><o g="{$g}"><xsl:variable name="local" select="$g * 2"/>'
    '<xsl:for-each select="/*/*"><xsl:variable name="p" select="position()"/><e p="{$p}" l="{$local}" s="{$s}"/></xsl:for-each></o></xsl:template>')
add('rtf', '<xsl:template match="/"><o><xsl:variable name="frag"><x>1</x><y>two</y></xsl:variable><xsl:copy-of select="$frag"/><s><xsl:value-of select="$frag"/></s>'
    '<xsl:variable name="names"><xsl:for-each select="//*"><xsl:value-of select="name()"/>,</xsl:for-each></xsl:variable><n><xsl:value-of select="$names"/></n></o></xsl:template>')
add('if-choose', '<xsl:template match="/"><o><xsl:for-each select="//*"><xsl:if test="@x"><has><xsl:value-of select="@x"/></has></xsl:if>'
    '<xsl:choose><xsl:when test="not(*)">leaf</xsl:when><xsl:when test="count(*) &gt; 2">wide</xsl:when><xsl:otherwise>mid</xsl:otherwise></xsl:choose></xsl:for-each></o></xsl:template>')
add('constructors', '<xsl:template match="/"><xsl:element name="out-{count(//*)}"><xsl:attribute name="a{1+1}">v<xsl:value-of select="name(/*)"/></xsl:attribute>'
    '<xsl:comment>made of <xsl:value-of select="count(//*)"/></xsl:comment><xsl:processing-instruction name="pi">data <xsl:value-of select="name(/*)"/></xsl:processing-instruction>'
    '<xsl:for-each select="/*/*[position() &lt; 3]"><xsl:element name="{name()}"><xsl:attribute name="n"><xsl:value-of select="position()"/></xsl:attribute></xsl:element></xsl:for-each></xsl:element></xsl:template>')
add('avt', '<xsl:template match="/"><o a="{{literal}}" b="{count(//*)}-{name(/*)}" c="x{1}y{2}z" d="{\'q\'}"/></xsl:template>')
add('copy-attrs', '<xsl:template match="/"><o><xsl:apply-templates select="//*[@*]"/></o></xsl:template><xsl:template match="*"><xsl:copy><xsl:copy-of select="@*"/><xsl:value-of select="name()"/></xsl:copy></xsl:template>')
add('copy-of-subtree', '<xsl:template match="/"><o><xsl:copy-of select="/*/*[1]"/><xsl:copy-of select="//@*[1]"/><xsl:copy-of select="count(//*)"/><xsl:copy-of select="\'str\'"/></o></xsl:template>')
add('functions', '<xsl:template match="/"><o><xsl:value-of select="concat(\'[\', string-length(string(/*)), \'|\', normalize-space(/*), \'|\', substring(name(/*), 1, 2), \'|\', translate(name(/*), \'abc\', \'ABC\'), \'|\', sum(//@x), \'|\', floor(count(//*) div 2), \']\')"/></o></xsl:template>')
add('position-last', '<xsl:template match="/"><o><xsl:for-each select="//*"><xsl:if test="position() = 1 or position() = last()"><e p="{position()}" l="{last()}"/></xsl:if></xsl:for-each></o></xsl:template>')
add('text-output', '<xsl:template match="/"><xsl:for-each select="//*"><xsl:value-of select="name()"/><xsl:text>:</xsl:text><xsl:value-of select="count(*)"/><xsl:text>&#10;</xsl:text></xsl:for-each></xsl:template>', 'text')
add('text-mixed', '<xsl:template match="*"><xsl:text>(</xsl:text><xsl:apply-templates/><xsl:text>)</xsl:text></xsl:template><xsl:template match="text()"><xsl:value-of select="normalize-space(.)"/></xsl:template>', 'text')
add('lre-namespaces', '<xsl:template match="/"><p:o><p:i q:a="1"/><xsl:for-each select="/*/*[position() &lt; 3]"><p:e n="{name()}"/></xsl:for-each></p:o></xsl:template>',
    extra='xmlns:p="urn:p" xmlns:q="urn:q"')
add('lre-excluded', '<xsl:template match="/"><o><i/></o></xsl:template>', extra='xmlns:p="urn:p" xmlns:q="urn:q" exclude-result-prefixes="p"')
add('default-ns', '<xsl:template match="/"><o><i><xsl:value-of select="count(//*)"/></i></o></xsl:template>', extra='xmlns="urn:d"')
add('xsl-element-ns', '<xsl:template match="/"><xsl:element name="o" namespace="urn:n"><xsl:element name="p:i" namespace="urn:pp"/><xsl:element name="j"/></xsl:element></xsl:template>')
add('xsl-element-prefixed', '<xsl:template match="/"><xsl:element name="p:o"><xsl:attribute name="p:a">1</xsl:attribute></xsl:element></xsl:template>', extra='xmlns:p="urn:p"')
add('copy-namespaced', '<xsl:template match="@*|node()"><xsl:copy><xsl:apply-templates select="@*|node()"/></xsl:copy></xsl:template>')
add('namespaced-match', '<xsl:template match="/"><o><xsl:apply-templates select="//p:*"/></o></xsl:template><xsl:template match="p:book"><b id="{@id}"><xsl:value-of select="p:title"/></b></xsl:template><xsl:template match="*"/>',
    extra='xmlns:p="urn:p"')
add('sort-numbers', '<xsl:template match="/"><o><xsl:for-each select="//*[@n or @x or @year]"><xsl:sort select="@n | @x | @year" data-type="number"/><v><xsl:value-of select="@n | @x | @year"/></v></xsl:for-each></o></xsl:template>')
add('apply-sort', '<xsl:template match="/"><o><xsl:apply-templates select="//*[@x]"><xsl:sort select="@x" data-type="number"/></xsl:apply-templates></o></xsl:template><xsl:template match="*"><i><xsl:value-of select="@x"/></i></xsl:template>')
add('params-pass', '<xsl:template match="/"><o><xsl:apply-templates select="/*/*"><xsl:with-param name="tag" select="\'T\'"/></xsl:apply-templates></o></xsl:template>'
    '<xsl:template match="*"><xsl:param name="tag" select="\'none\'"/><xsl:param name="extra">dflt</xsl:param><e t="{$tag}" x="{$extra}" n="{name()}"/></xsl:template>')
add('current', '<xsl:template match="/"><o><xsl:for-each select="//*[@x]"><m><xsl:value-of select="count(//*[@x = current()/@x])"/></m></xsl:for-each></o></xsl:template>')
add('generate-id', '<xsl:template match="/"><o><xsl:for-each select="//*"><xsl:if test="generate-id(.) = generate-id(/*)"><root/></xsl:if><xsl:if test="generate-id(.) != generate-id(/*)"><n/></xsl:if></xsl:for-each></o></xsl:template>')
add('nested-for-each', '<xsl:template match="/"><o><xsl:for-each select="/*/*"><g n="{name()}"><xsl:for-each select="*"><xsl:variable name="v" select="position()"/><c k="{$v}" p="{name(..)}"/></xsl:for-each></g></xsl:for-each></o></xsl:template>')
add('value-of-nodeset', '<xsl:template match="/"><o><a><xsl:value-of select="//*"/></a><b><xsl:value-of select="//@*"/></b><c><xsl:value-of select="/nothing"/></c><d><xsl:value-of select="1 div 4"/></d></o></xsl:template>')
add('numbers', '<xsl:template match="/"><o><xsl:value-of select="2 + 3"/>,<xsl:value-of select="10 div 4"/>,<xsl:value-of select="7 mod 3"/>,<xsl:value-of select="round(2.5)"/>,<xsl:value-of select="-0.5"/>,<xsl:value-of select="1 div 0"/>,<xsl:value-of select="count(//*) * 100"/>,<xsl:value-of select="0.5 + 0.25"/></o></xsl:template>')
add('comment-pi', '<xsl:template match="/"><o><xsl:copy-of select="//comment()"/><xsl:copy-of select="//processing-instruction()"/></o></xsl:template>')
add('template-recursion', '<xsl:template match="/"><o><xsl:apply-templates select="*"/></o></xsl:template><xsl:template match="*"><xsl:element name="{name()}"><xsl:attribute name="d"><xsl:value-of select="count(ancestor::*)"/></xsl:attribute><xsl:apply-templates select="*"/></xsl:element></xsl:template>')
add('text-whitespace', '<xsl:template match="/"><o>  <xsl:text> keep </xsl:text>  <i/>  </o></xsl:template>')
add('conflict-last', '<xsl:template match="/"><o><xsl:apply-templates select="/*"/></o></xsl:template><xsl:template match="*">first</xsl:template><xsl:template match="*">second</xsl:template>')
add('choose-nested', '<xsl:template match="/"><o><xsl:for-each select="//*"><xsl:choose><xsl:when test="@x"><xsl:choose><xsl:when test="@x &gt; 2">big</xsl:when><xsl:otherwise>small</xsl:otherwise></xsl:choose></xsl:when><xsl:otherwise>-</xsl:otherwise></xsl:choose></xsl:for-each></o></xsl:template>')
add('boolean-values', '<xsl:template match="/"><o><xsl:value-of select="boolean(//*)"/>,<xsl:value-of select="not(//zzz)"/>,<xsl:value-of select="count(//*) = count(descendant::*)"/>,<xsl:value-of select="string(false())"/></o></xsl:template>')
add('global-param', '<xsl:param name="p" select="\'default\'"/><xsl:template match="/"><o p="{$p}"/></xsl:template>')
add('attribute-set-by-value', '<xsl:template match="/"><o><xsl:for-each select="//*[@*]"><e><xsl:for-each select="@*"><xsl:attribute name="{name()}"><xsl:value-of select="."/>!</xsl:attribute></xsl:for-each></e></xsl:for-each></o></xsl:template>')
add('ancestors', '<xsl:template match="/"><o><xsl:for-each select="//*[not(*)]"><p><xsl:for-each select="ancestor-or-self::*"><xsl:value-of select="name()"/><xsl:if test="position() != last()">/</xsl:if></xsl:for-each></p></xsl:for-each></o></xsl:template>')
add('following', '<xsl:template match="/"><o><xsl:for-each select="/*/*[1]"><f><xsl:value-of select="count(following::*)"/></f><s><xsl:value-of select="count(following-sibling::*)"/></s><p><xsl:value-of select="count(preceding::*)"/></p></xsl:for-each></o></xsl:template>')
add('copy-shallow-doc', '<xsl:template match="/"><xsl:copy><xsl:apply-templates select="*"/></xsl:copy></xsl:template><xsl:template match="*"><xsl:copy><xsl:apply-templates/></xsl:copy></xsl:template>')
add('empty-result', '<xsl:template match="/"><o/></xsl:template>')
add('mixed-content-copy', '<xsl:template match="/"><o><xsl:copy-of select="//text()"/></o></xsl:template>')
add('sort-text-desc', '<xsl:template match="/"><o><xsl:for-each select="//*[text()]"><xsl:sort select="text()" order="descending"/><t><xsl:value-of select="text()"/></t></xsl:for-each></o></xsl:template>')
add('variable-rtf-count', '<xsl:template match="/"><o><xsl:variable name="nodes" select="//*"/><n><xsl:value-of select="count($nodes)"/></n><xsl:for-each select="$nodes[position() &lt; 3]"><k><xsl:value-of select="name()"/></k></xsl:for-each></o></xsl:template>')

DOCS = [
    '<r><a x="1" y="u">one</a><a x="2">two</a><b><a x="3" y="v">three<c/>tail</a><c>4</c><c>5.5</c></b><!-- note --><?pi data?><d>  spaced   out  </d><e/></r>',
    '<lib xmlns:p="urn:p"><p:book id="b1" year="1999"><p:title>First</p:title><p:price>10</p:price></p:book><p:book id="b2" year="2005"><p:title>Second</p:title><p:price>25.5</p:price></p:book><note>plain</note></lib>',
    '<t><s n="1">alpha</s><s n="3">gamma</s><s n="2">beta</s><g><s n="5">x</s><s n="6">y</s></g><u v="a b"> a  b </u></t>',
    '<m>text <i>italic</i> more <b>bold <i>both</i></b> end<?target some data?><!--c1--><n a="1" b="2"/><n a="3" b="2"/></m>',
    '<root xmlns="urn:d" xmlns:z="urn:z"><x z:k="1">one</x><z:y>two</z:y><x>three</x></root>',
]


def random_doc(depth=0):
    names = ['a', 'b', 'c', 'd', 'item', 'node']

    def build(d):
        tag = rnd.choice(names)
        attrs = ''
        if rnd.random() < 0.5:
            attrs += ' x="%d"' % rnd.randint(1, 9)
        if rnd.random() < 0.2:
            attrs += ' y="%s"' % rnd.choice(['u', 'v', 'w'])
        if d >= 3 or rnd.random() < 0.3:
            body = rnd.choice(['', 'txt', 'alpha', '7', 'beta'])
        else:
            body = ''.join(build(d + 1) for _ in range(rnd.randint(1, 3)))
        if body == '':
            return '<%s%s/>' % (tag, attrs)
        return '<%s%s>%s</%s>' % (tag, attrs, body, tag)
    return '<r>%s</r>' % ''.join(build(1) for _ in range(rnd.randint(2, 4)))


for _ in range(8):
    DOCS.append(random_doc())


def canon(result):
    bio = io.BytesIO()
    result.write_c14n(bio)
    return bio.getvalue().decode('utf-8')


pairs = []
for si, (name, text, method) in enumerate(S):
    xslt = ET.XSLT(ET.fromstring(text.encode('utf-8')))
    for di, doc in enumerate(DOCS):
        try:
            params = {}
            result = xslt(ET.fromstring(doc.encode('utf-8')), **params)
        except (ET.XSLTApplyError, ET.XSLTError):
            continue
        if method == 'text':
            expected = str(result)
            if not expected and False:
                continue
        else:
            if result.getroot() is None:
                continue
            try:
                expected = canon(result)
            except Exception:
                continue
        pairs.append((si, di, expected, method))


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


lines = []
lines.append('    let sheets = [%d]str{ %s }' % (len(S), ', '.join(quote(s[1]) for s in S)))
lines.append('    let docs = [%d]str{ %s }' % (len(DOCS), ', '.join(quote(d) for d in DOCS)))
CH = 120
for start in range(0, len(pairs), CH):
    chunk = pairs[start:start + CH]
    k = start // CH
    lines.append('    let p%d_sheet = [%d]usize{ %s }' % (k, len(chunk), ', '.join('%dusize' % c[0] for c in chunk)))
    lines.append('    let p%d_doc = [%d]usize{ %s }' % (k, len(chunk), ', '.join('%dusize' % c[1] for c in chunk)))
    lines.append('    let p%d_want = [%d]str{ %s }' % (k, len(chunk), ', '.join(quote(c[2]) for c in chunk)))
    lines.append('    let p%d_text = [%d]bool{ %s }' % (k, len(chunk), ', '.join('true' if c[3] == 'text' else 'false' for c in chunk)))
    lines.append('    var p%d_i = 0usize' % k)
    lines.append('    while p%d_i < %d {' % (k, len(chunk)))
    lines.append('        if !agrees(a, sheets[p%d_sheet[p%d_i]], docs[p%d_doc[p%d_i]], p%d_want[p%d_i], p%d_text[p%d_i]) { try report("p%d", p%d_i) }' % ((k,) * 10))
    lines.append('        p%d_i += 1usize' % k)
    lines.append('    }')

# refusals at load and a global parameter override, by hand
LOADS = [
    ('import', '<xsl:stylesheet version="1.0" %s><xsl:import href="x.xsl"/></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('include', '<xsl:stylesheet version="1.0" %s><xsl:include href="x.xsl"/></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('key', '<xsl:stylesheet version="1.0" %s><xsl:key name="k" match="a" use="@x"/></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('number', '<xsl:stylesheet version="1.0" %s><xsl:template match="/"><xsl:number/></xsl:template></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('html-output', '<xsl:stylesheet version="1.0" %s><xsl:output method="html"/></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('strip-space', '<xsl:stylesheet version="1.0" %s><xsl:strip-space elements="*"/></xsl:stylesheet>' % XSL, 'xs.Unsupported'),
    ('not-xsl', '<r/>', 'xs.Invalid'),
    ('no-match-or-name', '<xsl:stylesheet version="1.0" %s><xsl:template><o/></xsl:template></xsl:stylesheet>' % XSL, 'xs.Invalid'),
    ('bad-expression', '<xsl:stylesheet version="1.0" %s><xsl:template match="/"><xsl:value-of select="1 +"/></xsl:template></xsl:stylesheet>' % XSL, 'xs.Invalid'),
    ('bad-avt', '<xsl:stylesheet version="1.0" %s><xsl:template match="/"><o a="{1"/></xsl:template></xsl:stylesheet>' % XSL, 'xs.Invalid'),
    ('stray-top-level', '<xsl:stylesheet version="1.0" %s><o/></xsl:stylesheet>' % XSL, 'xs.Invalid'),
    ('good', '<xsl:stylesheet version="1.0" %s><xsl:template match="/"><o/></xsl:template></xsl:stylesheet>' % XSL, 'ok'),
]
for k, (label, text, want) in enumerate(LOADS):
    lines.append('    let (_, load_%d_error) = xs.load(a, %s)' % (k, quote(text)))
    lines.append('    if load_%d_error != %s { try report("load-%s", %dusize) }' % (k, want, label, k))
lines.append('    let override_sheet = %s' % quote(sheet('<xsl:param name="p" select="\'default\'"/><xsl:template match="/"><o p="{$p}"/></xsl:template>')))
lines.append('    let (override_ss, override_load) = xs.load(a, override_sheet)')
lines.append('    if override_load != ok { try report("override-load", 0usize) }')
lines.append('    let (override_doc, override_parse) = xml.parse(a, "<r/>")')
lines.append('    let (plain, plain_error) = xs.transform(a, &override_ss, &override_doc, zero)')
lines.append('    if plain_error != ok || !same(plain.text, "<o p=\\"default\\"/>\\n") { try report("param-default", 0usize) }')
lines.append('    let given = [1]xp.Variable{ xp.Variable { name: "p", value: xp.string_value("given") } }')
lines.append('    let (changed, changed_error) = xs.transform(a, &override_ss, &override_doc, given[..])')
lines.append('    if changed_error != ok || !same(changed.text, "<o p=\\"given\\"/>\\n") { try report("param-override", 0usize) }')
lines.append('    let terminate_sheet = %s' % quote(sheet('<xsl:template match="/"><xsl:message terminate="yes">stop</xsl:message></xsl:template>')))
lines.append('    let (terminate_ss, terminate_load) = xs.load(a, terminate_sheet)')
lines.append('    let (_, terminate_error) = xs.transform(a, &terminate_ss, &override_doc, zero)')
lines.append('    if terminate_load != ok || terminate_error != xs.Terminated { try report("terminate", 0usize) }')
lines.append('    let missing_sheet = %s' % quote(sheet('<xsl:template match="/"><xsl:call-template name="nothing"/></xsl:template>')))
lines.append('    let (missing_ss, missing_load) = xs.load(a, missing_sheet)')
lines.append('    let (_, missing_error) = xs.transform(a, &missing_ss, &override_doc, zero)')
lines.append('    if missing_load != ok || missing_error != xs.NoRule { try report("call-missing", 0usize) }')

body = '\n'.join(lines)
source = '''// e.fmt.xslt against libxslt through lxml (L081, D2274; scripts/xslt_reference.py writes this file): %d
// stylesheet and document pairs (%d stylesheets over %d documents), the result of each canonicalised (C14N)
// on both sides, a text-method result compared verbatim. A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.str
use e.fmt.xml as xml
use e.fmt.xpath as xp
use e.fmt.xslt as xs

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// ---- a C14N canonicaliser, so serialisation choices that mean nothing do not count ----

type Canon = struct { a: *mem.Arena, d: *const xml.Document, out: []u8, used: usize, prefixes: []str, uris: []str, depth: usize }

fn emit(c: *Canon, text: str) -> err {
    if c.used + text.len > c.out.len {
        var capacity = c.out.len * 2usize
        while capacity < c.used + text.len { capacity *= 2usize }
        let (bigger, alloc_error) = mem.alloc[u8](c.a, capacity)
        if alloc_error != ok { ret alloc_error }
        var i = 0usize
        while i < c.used {
            bigger[i] = c.out[i]
            i += 1usize
        }
        c.out = bigger
    }
    var k = 0usize
    while k < text.len {
        c.out[c.used] = text[k]
        c.used += 1usize
        k += 1usize
    }
    ret ok
}

fn emit_escaped(c: *Canon, text: str, attribute: bool) -> err {
    var i = 0usize
    while i < text.len {
        let ch = text[i]
        if ch == 38u8 {
            try emit(c, "&amp;")
        } else if ch == 60u8 {
            try emit(c, "&lt;")
        } else if ch == 62u8 && !attribute {
            try emit(c, "&gt;")
        } else if ch == 34u8 && attribute {
            try emit(c, "&quot;")
        } else if ch == 13u8 {
            try emit(c, "&#xD;")
        } else if attribute && ch == 9u8 {
            try emit(c, "&#x9;")
        } else if attribute && ch == 10u8 {
            try emit(c, "&#xA;")
        } else {
            try emit(c, text[i..i + 1usize])
        }
        i += 1usize
    }
    ret ok
}

fn rendered(c: *const Canon, prefix: str) -> (str, bool) {
    var i = c.depth
    while i > 0usize {
        i -= 1usize
        if same(c.prefixes[i], prefix) { ret (c.uris[i], true) }
    }
    ret ("", false)
}

fn canon_node(c: *Canon, id: u32) -> err {
    let n = c.d.nodes[usize(id)]
    if n.kind == .Text { ret emit_escaped(c, n.value, false) }
    if n.kind == .Comment {
        try emit(c, "<!--")
        try emit(c, n.value)
        ret emit(c, "-->")
    }
    if n.kind == .Processing {
        try emit(c, "<?")
        try emit(c, n.name)
        if n.value.len > 0usize {
            try emit(c, " ")
            try emit(c, n.value)
        }
        ret emit(c, "?>")
    }
    if n.kind == .Document {
        var child = n.first_child
        while child != 4294967295u32 {
            try canon_node(c, child)
            child = c.d.nodes[usize(child)].next_sibling
        }
        ret ok
    }
    let mark = c.depth
    try emit(c, "<")
    try emit(c, n.name)
    // own namespace declarations that change what is rendered, default first then by prefix
    var rounds = 0usize
    var previous = ""
    var first = true
    while rounds < n.attributes.len + 1usize {
        // the smallest prefix greater than the last one emitted
        var best = ""
        var best_uri = ""
        var found = false
        var i = 0usize
        while i < n.attributes.len {
            let name = n.attributes[i].name
            var prefix = ""
            var is_decl = false
            if same(name, "xmlns") { is_decl = true } else if str.starts_with(name, "xmlns:") {
                is_decl = true
                prefix = name[6usize..]
            }
            if is_decl && (first || str.compare(prefix, previous) > 0i32) && (!found || str.compare(prefix, best) < 0i32) {
                best = prefix
                best_uri = n.attributes[i].value
                found = true
            }
            i += 1usize
        }
        if !found { break }
        let (current, has_current) = rendered(c, best)
        var differs = false
        if has_current { differs = !same(current, best_uri) } else { differs = best_uri.len > 0usize }
        if differs {
            c.prefixes[c.depth] = best
            c.uris[c.depth] = best_uri
            c.depth += 1usize
            if best.len == 0usize {
                try emit(c, " xmlns=\\"")
            } else {
                try emit(c, " xmlns:")
                try emit(c, best)
                try emit(c, "=\\"")
            }
            try emit_escaped(c, best_uri, true)
            try emit(c, "\\"")
        }
        previous = best
        first = false
        rounds += 1usize
    }
    // attributes by (namespace, local name)
    var emitted_key_ns = ""
    var emitted_key_local = ""
    var any_emitted = false
    var guard = 0usize
    while guard < n.attributes.len + 1usize {
        var best_index = n.attributes.len
        var best_ns = ""
        var best_local = ""
        var i = 0usize
        while i < n.attributes.len {
            let name = n.attributes[i].name
            if !(same(name, "xmlns") || str.starts_with(name, "xmlns:")) {
                let (uri, local) = xp.expanded_name(c.d, xp.XNode { id: id, attribute: u32(i) + 1u32 })
                var after = !any_emitted
                if any_emitted {
                    let cmp_ns = str.compare(uri, emitted_key_ns)
                    after = cmp_ns > 0i32 || (cmp_ns == 0i32 && str.compare(local, emitted_key_local) > 0i32)
                }
                var smaller = best_index == n.attributes.len
                if !smaller {
                    let cmp_ns = str.compare(uri, best_ns)
                    smaller = cmp_ns < 0i32 || (cmp_ns == 0i32 && str.compare(local, best_local) < 0i32)
                }
                if after && smaller {
                    best_index = i
                    best_ns = uri
                    best_local = local
                }
            }
            i += 1usize
        }
        if best_index == n.attributes.len { break }
        try emit(c, " ")
        try emit(c, n.attributes[best_index].name)
        try emit(c, "=\\"")
        try emit_escaped(c, n.attributes[best_index].value, true)
        try emit(c, "\\"")
        emitted_key_ns = best_ns
        emitted_key_local = best_local
        any_emitted = true
        guard += 1usize
    }
    try emit(c, ">")
    var child = n.first_child
    while child != 4294967295u32 {
        try canon_node(c, child)
        child = c.d.nodes[usize(child)].next_sibling
    }
    try emit(c, "</")
    try emit(c, n.name)
    try emit(c, ">")
    c.depth = mark
    ret ok
}

fn canonical(a: *mem.Arena, d: *const xml.Document) -> (str, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, 4096usize)
    if buffer_error != ok { ret ("", buffer_error) }
    let (prefixes, prefixes_error) = mem.alloc[str](a, d.nodes.len * 4usize + 16usize)
    if prefixes_error != ok { ret ("", prefixes_error) }
    let (uris, uris_error) = mem.alloc[str](a, d.nodes.len * 4usize + 16usize)
    if uris_error != ok { ret ("", uris_error) }
    var c = Canon { a: a, d: d, out: buffer, used: 0usize, prefixes: prefixes, uris: uris, depth: 0usize }
    let walk_error = canon_node(&c, 0u32)
    if walk_error != ok { ret ("", walk_error) }
    ret (c.out[..c.used], ok)
}

fn agrees(a: *mem.Arena, sheet_text: str, doc_text: str, want: str, is_text: bool) -> bool {
    let checkpoint = mem.mark(a)
    var good = false
    let (ss, load_error) = xs.load(a, sheet_text)
    let (doc, parse_error) = xml.parse(a, doc_text)
    if load_error == ok && parse_error == ok {
        let (out, run_error) = xs.transform(a, &ss, &doc, zero)
        if run_error == ok {
            if is_text {
                good = same(out.text, want)
            } else {
                let (result_doc, result_error) = xml.parse(a, out.text)
                if result_error == ok {
                    let (text, text_error) = canonical(a, &result_doc)
                    good = text_error == ok && same(text, want)
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
    try io.print("xslt mismatch in ")
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
    try io.print("fmt xslt ok\\n")
    ret ok
}
''' % (len(pairs), len(S), len(DOCS))
source = source.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_xslt' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote fmt_xslt: %d pairs (%d stylesheets x %d docs)' % (len(pairs), len(S), len(DOCS)))
import json
import os

if os.environ.get('XSLT_DUMP'):
    json.dump({'sheets': [s[0] for s in S], 'pairs': [(p[0], p[1], p[2][:300]) for p in pairs], 'docs': DOCS}, open(os.environ['XSLT_DUMP'], 'w', encoding='utf-8'), ensure_ascii=False)
