"""Write tests/selfhost/fixtures/link/fmt_xsd_schema/src/main.e (L081, D2271 part 2: schema validation).

  python scripts/xsd_schema_reference.py

e.fmt.xsd.schema against libxml2's schema validator through lxml. Twenty-odd schemas cover the features the
validator implements (sequence, choice, all, occurrence bounds, attributes with use, fixed and default, simple
type restrictions and every facet, lists, unions, extension and restriction, simple and mixed and empty content,
groups, wildcards, ID and IDREF, namespaces and form defaults, nillable). Each has valid base instances; seeded
tree mutations (drop, duplicate, swap, rename or add an element, change, empty, truncate or extend text, add,
drop or change an attribute) produce several hundred more. lxml's verdict is the expected one; for an invalid
instance the library must also point at the same element lxml's first error names (compared as the element path)
unless the schema has a namespace, where only the verdict is compared. Disagreements that are libxml2 departing
from the specification are skipped with the reason in `SKIP`. A mismatch prints its table and index and exits 1.
"""
import copy
import pathlib
import random

import lxml.etree as ET

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261023)
XS = 'xmlns:xs="http://www.w3.org/2001/XMLSchema"'


def schema(body, extra=''):
    return '<xs:schema %s %s>%s</xs:schema>' % (XS, extra, body)


SCHEMAS = []


def add(name, xsd, instances, namespaced=False):
    SCHEMAS.append((name, xsd, instances, namespaced))


add('typed-sequence', schema('''<xs:element name="r"><xs:complexType><xs:sequence>
<xs:element name="s" type="xs:string"/><xs:element name="i" type="xs:int"/><xs:element name="d" type="xs:date"/>
<xs:element name="b" type="xs:boolean"/><xs:element name="m" type="xs:decimal"/><xs:element name="u" type="xs:unsignedByte" minOccurs="0"/>
</xs:sequence></xs:complexType></xs:element>'''), [
    '<r><s>x</s><i>5</i><d>2000-01-01</d><b>true</b><m>1.5</m></r>',
    '<r><s></s><i>-2147483648</i><d>2020-02-29</d><b>0</b><m>-0.25</m><u>255</u></r>',
    '<r>\n <s> padded </s>\n <i> 7 </i>\n <d>2000-12-31Z</d>\n <b>1</b>\n <m>3</m>\n</r>'])
add('occurs', schema('''<xs:element name="r"><xs:complexType><xs:sequence>
<xs:element name="a" type="xs:int" minOccurs="2" maxOccurs="4"/><xs:element name="b" type="xs:string" minOccurs="0" maxOccurs="unbounded"/>
<xs:element name="c" type="xs:int" minOccurs="0"/><xs:element name="d" type="xs:int" maxOccurs="2"/>
</xs:sequence></xs:complexType></xs:element>'''), [
    '<r><a>1</a><a>2</a><d>9</d></r>', '<r><a>1</a><a>2</a><a>3</a><a>4</a><b>x</b><b>y</b><c>1</c><d>1</d><d>2</d></r>', '<r><a>1</a><a>2</a><b/><d>0</d></r>'])
add('choice', schema('''<xs:element name="r"><xs:complexType><xs:sequence>
<xs:choice maxOccurs="3"><xs:element name="x" type="xs:int"/><xs:sequence><xs:element name="y" type="xs:string"/><xs:element name="z" type="xs:string" minOccurs="0"/></xs:sequence><xs:element name="w" type="xs:boolean"/></xs:choice>
<xs:choice minOccurs="0"><xs:element name="p" type="xs:int"/><xs:element name="q" type="xs:int"/></xs:choice>
</xs:sequence></xs:complexType></xs:element>'''), [
    '<r><x>1</x></r>', '<r><y>a</y><z>b</z><w>true</w></r>', '<r><w>1</w><x>2</x><y>q</y><q>3</q></r>', '<r><y>only</y><p>1</p></r>'])
add('all', schema('''<xs:element name="r"><xs:complexType><xs:all>
<xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:string"/><xs:element name="c" type="xs:int" minOccurs="0"/>
</xs:all></xs:complexType></xs:element>'''), [
    '<r><a>1</a><b>x</b></r>', '<r><c>3</c><b>x</b><a>1</a></r>', '<r><b>x</b><a>1</a><c>2</c></r>'])
add('attributes', schema('''<xs:attributeGroup name="common"><xs:attribute name="id" type="xs:int" use="required"/><xs:attribute name="label" type="xs:string"/></xs:attributeGroup>
<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="item" maxOccurs="unbounded"><xs:complexType><xs:attributeGroup ref="common"/>
<xs:attribute name="kind" type="xs:token" fixed="std"/><xs:attribute name="level" type="xs:byte" default="3"/><xs:attribute name="on" type="xs:boolean" use="optional"/></xs:complexType></xs:element></xs:sequence>
<xs:attribute name="version" type="xs:decimal" use="required"/></xs:complexType></xs:element>'''), [
    '<r version="1.0"><item id="1"/></r>', '<r version="2"><item id="1" label="x" kind="std" level="-128" on="true"/><item id="2" on="0"/></r>',
    '<r version="1.5"><item id="3" level="127" kind=" std "/></r>'])
add('facets', schema('''<xs:simpleType name="Code"><xs:restriction base="xs:string"><xs:pattern value="[A-Z]{2}[0-9]{3}"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Color"><xs:restriction base="xs:string"><xs:enumeration value="red"/><xs:enumeration value="green"/><xs:enumeration value="blue"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Short3"><xs:restriction base="xs:string"><xs:minLength value="2"/><xs:maxLength value="5"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Fixed4"><xs:restriction base="xs:string"><xs:length value="4"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Pct"><xs:restriction base="xs:integer"><xs:minInclusive value="0"/><xs:maxInclusive value="100"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Pos"><xs:restriction base="xs:decimal"><xs:minExclusive value="0"/><xs:maxExclusive value="10"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Money"><xs:restriction base="xs:decimal"><xs:totalDigits value="6"/><xs:fractionDigits value="2"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Collapsed"><xs:restriction base="xs:string"><xs:whiteSpace value="collapse"/><xs:enumeration value="a b"/></xs:restriction></xs:simpleType>
<xs:simpleType name="NumEnum"><xs:restriction base="xs:decimal"><xs:enumeration value="1.5"/><xs:enumeration value="2"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Hex2"><xs:restriction base="xs:hexBinary"><xs:length value="2"/></xs:restriction></xs:simpleType>
<xs:element name="r"><xs:complexType><xs:sequence>
<xs:element name="code" type="Code"/><xs:element name="color" type="Color"/><xs:element name="short" type="Short3"/><xs:element name="fixed" type="Fixed4"/>
<xs:element name="pct" type="Pct"/><xs:element name="pos" type="Pos"/><xs:element name="money" type="Money"/><xs:element name="coll" type="Collapsed"/>
<xs:element name="num" type="NumEnum"/><xs:element name="hex" type="Hex2"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><code>AB123</code><color>red</color><short>abc</short><fixed>abcd</fixed><pct>50</pct><pos>5.5</pos><money>1234.56</money><coll>a b</coll><num>1.50</num><hex>ABcd</hex></r>',
    '<r><code>ZZ999</code><color>blue</color><short>ab</short><fixed>日本語x</fixed><pct>0</pct><pos>0.0001</pos><money>-9999.99</money><coll>  a   b </coll><num>2.0</num><hex>0000</hex></r>',
    '<r><code>QQ000</code><color>green</color><short>abcde</short><fixed>1234</fixed><pct>100</pct><pos>9.9999</pos><money>0</money><coll>a b</coll><num>2</num><hex>ff00</hex></r>'])
add('list-union', schema('''<xs:simpleType name="Ints"><xs:list itemType="xs:int"/></xs:simpleType>
<xs:simpleType name="Ints3"><xs:restriction base="Ints"><xs:maxLength value="3"/></xs:restriction></xs:simpleType>
<xs:simpleType name="IntOrWord"><xs:union memberTypes="xs:int"><xs:simpleType><xs:restriction base="xs:string"><xs:enumeration value="none"/><xs:enumeration value="all"/></xs:restriction></xs:simpleType></xs:union></xs:simpleType>
<xs:simpleType name="Dates"><xs:list><xs:simpleType><xs:restriction base="xs:date"/></xs:simpleType></xs:list></xs:simpleType>
<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="ints" type="Ints"/><xs:element name="few" type="Ints3"/><xs:element name="mix" type="IntOrWord" maxOccurs="2"/><xs:element name="dates" type="Dates" minOccurs="0"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><ints>1 2 3</ints><few>1</few><mix>5</mix></r>', '<r><ints></ints><few>1 2 3</few><mix>none</mix><mix>all</mix><dates>2000-01-01 2001-02-03</dates></r>', '<r><ints>  -1   0 </ints><few></few><mix>-7</mix></r>'])
add('extension', schema('''<xs:complexType name="Base"><xs:sequence><xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:string" minOccurs="0"/></xs:sequence><xs:attribute name="x" type="xs:int"/></xs:complexType>
<xs:complexType name="Ext"><xs:complexContent><xs:extension base="Base"><xs:sequence><xs:element name="c" type="xs:boolean"/></xs:sequence><xs:attribute name="y" type="xs:string" use="required"/></xs:extension></xs:complexContent></xs:complexType>
<xs:element name="r" type="Ext"/>'''), [
    '<r y="k"><a>1</a><c>true</c></r>', '<r x="3" y="k"><a>1</a><b>s</b><c>0</c></r>'])
add('simple-content', schema('''<xs:complexType name="Price"><xs:simpleContent><xs:extension base="xs:decimal"><xs:attribute name="cur" type="xs:string" use="required"/></xs:extension></xs:simpleContent></xs:complexType>
<xs:complexType name="Small"><xs:simpleContent><xs:restriction base="Price"><xs:maxInclusive value="100"/></xs:restriction></xs:simpleContent></xs:complexType>
<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="p" type="Price"/><xs:element name="s" type="Small" minOccurs="0"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><p cur="EUR">12.50</p></r>', '<r><p cur="USD">-3</p><s cur="X">100</s></r>'])
add('mixed-empty', schema('''<xs:element name="r"><xs:complexType><xs:sequence>
<xs:element name="para"><xs:complexType mixed="true"><xs:sequence><xs:element name="b" type="xs:string" minOccurs="0" maxOccurs="unbounded"/></xs:sequence></xs:complexType></xs:element>
<xs:element name="e"><xs:complexType><xs:attribute name="v" type="xs:int"/></xs:complexType></xs:element>
</xs:sequence></xs:complexType></xs:element>'''), [
    '<r><para>hello <b>bold</b> world</para><e/></r>', '<r><para/><e v="3"/></r>', '<r><para>text only</para><e v="-1"></e></r>'])
add('groups', schema('''<xs:group name="g"><xs:sequence><xs:element name="p" type="xs:int"/><xs:element name="q" type="xs:int" minOccurs="0"/></xs:sequence></xs:group>
<xs:group name="h"><xs:choice><xs:element name="m" type="xs:string"/><xs:group ref="g"/></xs:choice></xs:group>
<xs:element name="r"><xs:complexType><xs:sequence><xs:group ref="h" maxOccurs="2"/><xs:element name="end" type="xs:string"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><m>x</m><end>.</end></r>', '<r><p>1</p><q>2</q><m>y</m><end>.</end></r>', '<r><p>1</p><p>2</p><end>e</end></r>'])
add('wildcard', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int"/><xs:any namespace="##other" minOccurs="0" maxOccurs="3" processContents="lax"/><xs:element name="z" type="xs:int"/></xs:sequence><xs:anyAttribute namespace="##other" processContents="lax"/></xs:complexType></xs:element>''',
                       'targetNamespace="urn:t" xmlns="urn:t" elementFormDefault="qualified"'), [
    '<r xmlns="urn:t"><a>1</a><z>2</z></r>', '<r xmlns="urn:t" xmlns:o="urn:o" o:k="v"><a>1</a><o:note>hi</o:note><o:other/><z>2</z></r>', '<r xmlns="urn:t" xmlns:o="urn:o"><a>1</a><o:x/><o:y>1</o:y><o:z/><z>1</z></r>'], True)
add('wildcard-list', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:any namespace="urn:x urn:y" maxOccurs="unbounded" processContents="skip"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r xmlns:x="urn:x" xmlns:y="urn:y"><x:a/><y:b>t</y:b></r>', '<r xmlns:x="urn:x"><x:a/><x:a><x:b/></x:a></r>'], True)
add('ids', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="n" maxOccurs="unbounded"><xs:complexType><xs:attribute name="id" type="xs:ID" use="required"/><xs:attribute name="next" type="xs:IDREF"/></xs:complexType></xs:element></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><n id="a"/><n id="b" next="a"/></r>', '<r><n id="x1" next="x1"/></r>', '<r><n id="q" next="z"/><n id="z"/></r>'])
add('namespaced', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:string" minOccurs="0" maxOccurs="2"/><xs:element name="u" type="xs:int" form="unqualified" minOccurs="0"/></xs:sequence><xs:attribute name="k" type="xs:int"/></xs:complexType></xs:element>''',
                        'targetNamespace="urn:t" xmlns="urn:t" elementFormDefault="qualified"'), [
    '<r xmlns="urn:t"><a>1</a></r>', '<t:r xmlns:t="urn:t" k="2"><t:a>1</t:a><t:b>x</t:b><u xmlns="">5</u></t:r>'], True)
add('nillable', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int" nillable="true"/><xs:element name="b" type="xs:string"/></xs:sequence></xs:complexType></xs:element>''',
                       ''), [
    '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><a xsi:nil="true"/><b>x</b></r>', '<r xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><a xsi:nil="false">3</a><b>x</b></r>'])
add('anonymous', schema('''<xs:element name="r"><xs:complexType><xs:sequence>
<xs:element name="age"><xs:simpleType><xs:restriction base="xs:int"><xs:minInclusive value="0"/><xs:maxInclusive value="150"/></xs:restriction></xs:simpleType></xs:element>
<xs:element name="tags"><xs:simpleType><xs:list><xs:simpleType><xs:restriction base="xs:token"><xs:maxLength value="4"/></xs:restriction></xs:simpleType></xs:list></xs:simpleType></xs:element>
<xs:element ref="extra" minOccurs="0"/></xs:sequence></xs:complexType></xs:element>
<xs:element name="extra"><xs:complexType><xs:sequence><xs:element name="v" type="xs:double"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><age>30</age><tags>a bb ccc dddd</tags></r>', '<r><age>0</age><tags></tags><extra><v>1e3</v></extra></r>', '<r><age>150</age><tags>x</tags><extra><v>NaN</v></extra></r>'])
add('temporal', schema('''<xs:simpleType name="Window"><xs:restriction base="xs:dateTime"><xs:minInclusive value="2000-01-01T00:00:00Z"/><xs:maxExclusive value="2030-01-01T00:00:00Z"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Day"><xs:restriction base="xs:date"><xs:minInclusive value="2020-01-01Z"/><xs:maxInclusive value="2020-12-31Z"/></xs:restriction></xs:simpleType>
<xs:simpleType name="Office"><xs:restriction base="xs:time"><xs:minInclusive value="09:00:00Z"/><xs:maxInclusive value="17:30:00Z"/></xs:restriction></xs:simpleType>
<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="w" type="Window"/><xs:element name="d" type="Day"/><xs:element name="t" type="Office"/><xs:element name="dur" type="xs:duration" minOccurs="0"/><xs:element name="y" type="xs:gYear" minOccurs="0"/></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><w>2010-05-05T12:00:00Z</w><d>2020-06-01Z</d><t>09:00:00Z</t></r>', '<r><w>2000-01-01T00:00:00Z</w><d>2020-12-31Z</d><t>17:30:00Z</t><dur>P1DT2H</dur><y>1999</y></r>',
    '<r><w>2029-12-31T23:59:59Z</w><d>2020-01-01Z</d><t>12:00:00Z</t></r>'])
add('restriction-complex', schema('''<xs:complexType name="Base"><xs:sequence><xs:element name="a" type="xs:int" minOccurs="0"/><xs:element name="b" type="xs:int" minOccurs="0" maxOccurs="3"/></xs:sequence><xs:attribute name="p" type="xs:int"/><xs:attribute name="q" type="xs:int"/></xs:complexType>
<xs:complexType name="Narrow"><xs:complexContent><xs:restriction base="Base"><xs:sequence><xs:element name="a" type="xs:int"/><xs:element name="b" type="xs:int" maxOccurs="2"/></xs:sequence><xs:attribute name="q" use="prohibited"/></xs:restriction></xs:complexContent></xs:complexType>
<xs:element name="r" type="Narrow"/>'''), [
    '<r><a>1</a><b>2</b></r>', '<r p="4"><a>1</a><b>2</b><b>3</b></r>'])
add('deep-nesting', schema('''<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="l1" maxOccurs="2"><xs:complexType><xs:sequence><xs:element name="l2" maxOccurs="unbounded"><xs:complexType><xs:sequence><xs:element name="v" type="xs:int"/><xs:element name="w" type="xs:string" minOccurs="0"/></xs:sequence><xs:attribute name="n" type="xs:int"/></xs:complexType></xs:element></xs:sequence></xs:complexType></xs:element></xs:sequence></xs:complexType></xs:element>'''), [
    '<r><l1><l2 n="1"><v>1</v></l2><l2><v>2</v><w>x</w></l2></l1></r>', '<r><l1><l2><v>1</v></l2></l1><l1><l2 n="9"><v>3</v><w/></l2></l1></r>'])

# libxml2 departures from the specification that the mutation corpus can reach. A skipped candidate is covered by
# SPEC_INSTANCES with the verdict the specification gives.
def spec_skip(name, text):
    if name == 'ids':
        tree = ET.fromstring(text.encode('utf-8'))
        ids = {n.get('id') for n in tree.iter() if n.get('id') is not None}
        refs = [n.get('next') for n in tree.iter() if n.get('next') is not None]
        if any(r not in ids for r in refs):
            return 'libxml2 does not check that an IDREF matches an ID'
    if name == 'temporal':
        import re
        tree = ET.fromstring(text.encode('utf-8'))
        for n in tree.iter():
            if n.tag in ('w', 'd', 't') and n.text and not re.search(r'(Z|[+-]\d\d:\d\d)\s*$', n.text) and re.match(r'\s*[\d-]', n.text):
                return 'libxml2 orders zoneless values against zoned bounds by its own rule; the specification leaves them indeterminate'
            if n.text is not None and len(n) == 0 and n.text != n.text.strip(' \t\n'):
                return 'libxml2 does not collapse whitespace in date, time, duration and g* types'
    return None


SPEC_INSTANCES = {
    'nillable': [],
    'temporal': [('<r><w>2029-12-31T23:59:59</w><d>2020-01-01Z</d><t>12:00:00Z</t></r>', False), ('<r><w>2010-05-05T12:00:00Z</w><d>2020-06-01Z</d><t>12:00:00</t></r>', False), ('<r><w>2010-05-05T12:00:00Z</w><d>2020-06-01Z</d><t>17:30:00</t></r>', False), ('<r><w>2010-05-05T12:00:00</w><d>2020-06-01Z</d><t>12:00:00Z</t></r>', True), ('<r><w>2010-05-05T12:00:00Z</w><d>2020-06-01Z </d><t> 09:00:00Z</t><y> 1999 </y></r>', True), ('<r><w>2010-05-05T12:00:00Z</w><d>2020-06-01Z</d><t>12:00:00Z </t><dur>\nP1D </dur></r>', True)],
    'ids': [('<r><n id="q" next="z"/></r>', False), ('<r><n id="q" next="z"/><n id="bad"/></r>', False), ('<r><n id="a"/><n id="b" next="a"/><n id="c" next="b"/></r>', True),
            ('<r><n id="a"/><n id="a"/></r>', False)],
}


def libxml_result(sch, text):
    try:
        doc = ET.fromstring(text.encode('utf-8'))
    except ET.XMLSyntaxError:
        return None
    ok = sch.validate(doc)
    path = None
    if not ok and len(sch.error_log):
        path = sch.error_log[0].path
    return bool(ok), path


def mutate(text):
    tree = ET.fromstring(text.encode('utf-8'))
    elements = list(tree.iter())
    nodes = [e for e in elements if isinstance(e.tag, str)]
    op = rnd.randrange(14)
    target = rnd.choice(nodes)
    parent = target.getparent()
    if op == 0 and parent is not None:
        parent.remove(target)
    elif op == 1 and parent is not None:
        parent.insert(parent.index(target), copy.deepcopy(target))
    elif op == 2 and parent is not None and len(parent) > 1:
        sibs = list(parent)
        i, j = rnd.sample(range(len(sibs)), 2)
        sibs[i], sibs[j] = sibs[j], sibs[i]
        for c in list(parent):
            parent.remove(c)
        for c in sibs:
            parent.append(c)
    elif op == 3:
        target.append(ET.Element('zzz'))
    elif op == 4:
        target.text = rnd.choice(['x', '', ' ', 'true', '-1', '1.5', '99999999999', 'NaN', '2000-13-01', 'Ab', 'a b'])
    elif op == 5 and target.text:
        target.text = target.text[:-1]
    elif op == 6:
        target.text = (target.text or '') + rnd.choice(['0', 'x', ' ', '.'])
    elif op == 7:
        target.set('zz', '1')
    elif op == 8 and len(target.attrib):
        del target.attrib[rnd.choice(list(target.attrib))]
    elif op == 9 and len(target.attrib):
        k = rnd.choice(list(target.attrib))
        target.set(k, rnd.choice(['bad', '', '0', '-1', '1', '300', 'true', 'std', 'other']))
    elif op == 10 and parent is not None:
        target.tag = target.tag + 'x' if rnd.random() < 0.5 else 'a'
    elif op == 11:
        target.text = (target.text or '') + 'stray'
    elif op == 12 and parent is not None:
        target.tail = 'tail'
    elif op == 13:
        # duplicate the whole last child
        if len(target):
            target.append(copy.deepcopy(target[-1]))
    return ET.tostring(tree, encoding='unicode')


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
valid_count = 0
path_checked = 0
for k, (name, xsd, bases, namespaced) in enumerate(SCHEMAS):
    sch = ET.XMLSchema(ET.fromstring(xsd.encode('utf-8')))
    cases = []
    seen = set()
    for b in bases:
        res = libxml_result(sch, b)
        assert res is not None and res[0], (name, b, sch.error_log)
        if b not in seen:
            seen.add(b)
            cases.append((b, True, ''))
    attempts = 0
    while len(cases) < 90 and attempts < 4000:
        attempts += 1
        base = rnd.choice(bases)
        text = base
        for _ in range(rnd.randint(1, 2)):
            text = mutate(text)
        if text in seen:
            continue
        res = libxml_result(sch, text)
        if res is None or spec_skip(name, text):
            continue
        seen.add(text)
        ok, path = res
        cases.append((text, ok, '' if ok else (path or '')))
    assert any(not c[1] for c in cases), name
    for text, want in SPEC_INSTANCES.get(name, []):
        cases.append((text, want, ''))
    DUMP[name] = [(c[0], c[1], c[2]) for c in cases]
    total += len(cases)
    valid_count += sum(c[1] for c in cases)
    var = 'schema_%d' % k
    lines.append('    let %s_xsd = %s' % (var, quote(xsd)))
    lines.append('    let (%s, %s_error) = sx.load(a, %s_xsd)' % (var, var, var))
    lines.append('    if %s_error != ok { try report("load-%s", 0usize) }' % (var, name))
    lines.append('    let %s_docs = [%d]str{ %s }' % (var, len(cases), ', '.join(quote(c[0]) for c in cases)))
    lines.append('    let %s_want = [%d]bool{ %s }' % (var, len(cases), ', '.join('true' if c[1] else 'false' for c in cases)))
    lines.append('    let %s_paths = [%d]str{ %s }' % (var, len(cases), ', '.join(quote(c[2]) for c in cases)))
    lines.append('    var %s_i = 0usize' % var)
    lines.append('    while %s_i < %d {' % (var, len(cases)))
    lines.append('        let (%s_doc, %s_parse_error) = xml.parse(a, %s_docs[%s_i])' % (var, var, var, var))
    lines.append('        if %s_parse_error != ok { try report("parse-%s", %s_i) }' % (var, name, var))
    lines.append('        let (%s_result, %s_run_error) = sx.validate(a, &%s, &%s_doc)' % (var, var, var, var))
    lines.append('        if %s_run_error != ok || %s_result.valid != %s_want[%s_i] { try report("verdict-%s", %s_i) }' % (var, var, var, var, name, var))
    if not namespaced:
        lines.append('        if !%s_result.valid {' % var)
        lines.append('            let (%s_path, %s_path_error) = sx.node_path(a, &%s_doc, %s_result.node)' % (var, var, var, var))
        lines.append('            if %s_path_error != ok || (%s_paths[%s_i].len > 0usize && !same(%s_path, %s_paths[%s_i])) { try report("path-%s", %s_i) }' % (var, var, var, var, var, var, name, var))
        lines.append('        }')
        path_checked += sum(1 for c in cases if not c[1])
    lines.append('        %s_i += 1usize' % var)
    lines.append('    }')

# load refusals and a few result-shape checks, by hand
LOADS = [
    ('import', schema('<xs:import namespace="urn:x" schemaLocation="x.xsd"/><xs:element name="r" type="xs:int"/>'), 'sx.Unsupported'),
    ('include', schema('<xs:include schemaLocation="x.xsd"/>'), 'sx.Unsupported'),
    ('redefine', schema('<xs:redefine schemaLocation="x.xsd"/>'), 'sx.Unsupported'),
    ('key', schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int"/></xs:sequence></xs:complexType><xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="."/></xs:key></xs:element>'), 'sx.Unsupported'),
    ('top-key', schema('<xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="."/></xs:key>'), 'sx.Unsupported'),
    ('substitution', schema('<xs:element name="h" type="xs:int"/><xs:element name="m" type="xs:int" substitutionGroup="h"/>'), 'sx.Unsupported'),
    ('abstract-local', schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int" abstract="true"/></xs:sequence></xs:complexType></xs:element>'), 'sx.Unsupported'),
    ('unresolved-type', schema('<xs:element name="r" type="Nope"/>'), 'sx.Unresolved'),
    ('unresolved-prefix', schema('<xs:element name="r" type="zz:Nope"/>'), 'sx.Unresolved'),
    ('unresolved-ref', schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element ref="gone"/></xs:sequence></xs:complexType></xs:element>'), 'sx.Unresolved'),
    ('unresolved-group', schema('<xs:element name="r"><xs:complexType><xs:group ref="gone"/></xs:complexType></xs:element>'), 'sx.Unresolved'),
    ('duplicate-type', schema('<xs:simpleType name="T"><xs:restriction base="xs:int"/></xs:simpleType><xs:simpleType name="T"><xs:restriction base="xs:int"/></xs:simpleType>'), 'sx.Invalid'),
    ('duplicate-element', schema('<xs:element name="r" type="xs:int"/><xs:element name="r" type="xs:string"/>'), 'sx.Invalid'),
    ('unnamed-type', schema('<xs:simpleType><xs:restriction base="xs:int"/></xs:simpleType>'), 'sx.Invalid'),
    ('min-over-max', schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int" minOccurs="3" maxOccurs="2"/></xs:sequence></xs:complexType></xs:element>'), 'sx.Invalid'),
    ('bad-occurs', schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int" minOccurs="x"/></xs:sequence></xs:complexType></xs:element>'), 'sx.Invalid'),
    ('not-schema', '<r/>', 'sx.Invalid'),
    ('wrong-ns-schema', '<xs:schema xmlns:xs="urn:other"><xs:element name="r" type="xs:int"/></xs:schema>', 'sx.Invalid'),
    ('pattern-category', schema('<xs:simpleType name="T"><xs:restriction base="xs:string"><xs:pattern value="\\p{L}+"/></xs:restriction></xs:simpleType>'), 'sx.Unsupported'),
    ('pattern-subtraction', schema('<xs:simpleType name="T"><xs:restriction base="xs:string"><xs:pattern value="[a-z-[aeiou]]"/></xs:restriction></xs:simpleType>'), 'sx.Unsupported'),
    ('pattern-initial', schema('<xs:simpleType name="T"><xs:restriction base="xs:string"><xs:pattern value="\\i\\c*"/></xs:restriction></xs:simpleType>'), 'sx.Unsupported'),
    ('empty-union', schema('<xs:simpleType name="T"><xs:union/></xs:simpleType>'), 'sx.Invalid'),
    ('empty-simple-type', schema('<xs:simpleType name="T"/>'), 'sx.Invalid'),
    ('good', schema('<xs:element name="r" type="xs:int"/>'), 'ok'),
]
for k, (label, text, want) in enumerate(LOADS):
    lines.append('    let load_%d_xsd = %s' % (k, quote(text)))
    lines.append('    let (load_%d, load_%d_error) = sx.load(a, load_%d_xsd)' % (k, k, k))
    lines.append('    if load_%d_error != %s { try report("load-%s", %dusize) }' % (k, want, label, k))
# results for odd roots and namespaces
lines.append('    let root_xsd = %s' % quote(schema('<xs:element name="r" type="xs:int"/>', 'targetNamespace="urn:t"')))
lines.append('    let (root_schema, root_load_error) = sx.load(a, root_xsd)')
lines.append('    if root_load_error != ok { try report("root-load", 0usize) }')
for k, (text, want_valid, code) in enumerate([
        ('<r xmlns="urn:t">5</r>', True, 'None'), ('<r>5</r>', False, 'UnknownRoot'), ('<t:r xmlns:t="urn:t">x</t:r>', False, 'BadValue'),
        ('<q xmlns="urn:t">5</q>', False, 'UnknownRoot'), ('<r xmlns="urn:t" a="1">5</r>', False, 'UnknownAttribute'), ('<r xmlns="urn:t"><c/></r>', False, 'UnexpectedElement')]):
    lines.append('    let (root_%d, root_%d_error) = sx.validate_text(a, &root_schema, %s)' % (k, k, quote(text)))
    lines.append('    if root_%d_error != ok || root_%d.valid != %s || root_%d.code != sx.ErrorCode.%s { try report("root-result", %dusize) }' % (k, k, 'true' if want_valid else 'false', k, code, k))
lines.append('    let (_, malformed_error) = sx.validate_text(a, &root_schema, "<r xmlns=\\"urn:t\\">")')
lines.append('    if malformed_error == ok { try report("malformed-instance", 0usize) }')
lines.append('    let (_, malformed_schema_error) = sx.load(a, "<xs:schema")')
lines.append('    if malformed_schema_error == ok { try report("malformed-schema", 0usize) }')
# error nodes: the node named by the result is the element the error concerns
lines.append('    let paths_xsd = %s' % quote(schema('<xs:element name="r"><xs:complexType><xs:sequence><xs:element name="a" type="xs:int" maxOccurs="2"/><xs:element name="b" type="xs:int"/></xs:sequence></xs:complexType></xs:element>')))
lines.append('    let (paths_schema, paths_load_error) = sx.load(a, paths_xsd)')
lines.append('    if paths_load_error != ok { try report("paths-load", 0usize) }')
lines.append('    let (path_doc, path_parse_error) = xml.parse(a, "<r><a>1</a><a>2</a><a>3</a><b>4</b></r>")')
lines.append('    if path_parse_error != ok { try report("paths-parse", 0usize) }')
lines.append('    let (path_result, path_run_error) = sx.validate(a, &paths_schema, &path_doc)')
lines.append('    let (path_text, path_text_error) = sx.node_path(a, &path_doc, path_result.node)')
lines.append('    if path_run_error != ok || path_text_error != ok || path_result.valid || !same(path_text, "/r/a[3]") { try report("node-path", 0usize) }')
lines.append('    let (path_missing, path_missing_parse) = xml.parse(a, "<r><a>1</a></r>")')
lines.append('    let (missing_result, missing_run) = sx.validate(a, &paths_schema, &path_missing)')
lines.append('    let (missing_text, missing_text_error) = sx.node_path(a, &path_missing, missing_result.node)')
lines.append('    if path_missing_parse != ok || missing_run != ok || missing_text_error != ok || missing_result.code != sx.ErrorCode.MissingContent || !same(missing_text, "/r") { try report("node-path", 1usize) }')

body = '\n'.join(lines)
source = '''// e.fmt.xsd.schema against libxml2's schema validator through lxml (L081, D2271 part 2; scripts/
// xsd_schema_reference.py writes this file): %d instances of %d schemas (base instances and seeded tree
// mutations), each with libxml2's verdict and, for invalid ones in schemas with no namespace, the path of the
// element libxml2's first error names. A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.fmt.xml as xml
use e.fmt.xsd.schema as sx

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
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
    try io.print("schema mismatch in ")
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
    try io.print("fmt xsd schema ok\\n")
    ret ok
}
''' % (total, len(SCHEMAS))
source = source.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_xsd_schema' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote fmt_xsd_schema: %d instances (%d valid) over %d schemas, %d paths compared' % (total, valid_count, len(SCHEMAS), path_checked))

import json
import os

if os.environ.get('XSD_DUMP'):
    json.dump(DUMP, open(os.environ['XSD_DUMP'], 'w', encoding='utf-8'), ensure_ascii=False)
