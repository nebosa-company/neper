"""Write tests/selfhost/fixtures/link/fmt_soap/src/main.e (L080, D2270).

  python scripts/soap_reference.py

e.fmt.soap against Python's xml.etree. Canned SOAP 1.1 and 1.2 documents (requests, responses, faults,
custom prefixes, a default-namespace envelope, mustUnderstand headers, malformed shapes) are analysed by an
ElementTree-based reference written separately from the library and compared: error kind, version, payload
element, the must-understand blocks, and every fault field. The builder's output is compared with the
reference's own serialisation and re-parsed by ElementTree to prove it is well-formed. Canned WSDL 1.1
documents (document/literal and rpc/encoded, SOAP 1.1 and 1.2 bindings) are compared for operations, actions,
styles, message parts and the service address. The XSD built-in mapping is compared with a table. A mismatch
prints its table and index and exits 1.
"""
import pathlib
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
NS11 = 'http://schemas.xmlsoap.org/soap/envelope/'
NS12 = 'http://www.w3.org/2003/05/soap-envelope'
WSDL = 'http://schemas.xmlsoap.org/wsdl/'
WSOAP11 = 'http://schemas.xmlsoap.org/wsdl/soap/'
WSOAP12 = 'http://schemas.xmlsoap.org/wsdl/soap12/'


def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def qn(tag):
    if tag.startswith('{'):
        uri, local = tag[1:].split('}')
        return uri, local
    return '', tag


def ns_map(text):
    nsmap = {}
    for _, (prefix, uri) in ET.iterparse(__import__('io').StringIO(text), events=('start-ns',)):
        nsmap[prefix] = uri
    return nsmap


def analyse(text):
    """The reference verdict for one document."""
    nsmap = ns_map(text)
    el = ET.fromstring(text)
    uri, local = qn(el.tag)
    if local != 'Envelope':
        return {'error': 'NotSoap'}
    if uri == NS12:
        version = 12
    elif uri == NS11:
        version = 11
    else:
        return {'error': 'VersionMismatch'}
    children = list(el)
    header = body = None
    seen_body = False
    for c in children:
        cu, cl = qn(c.tag)
        if cu == uri and cl == 'Header':
            if header is not None or seen_body:
                return {'error': 'Invalid'}
            header = c
        elif cu == uri and cl == 'Body':
            if seen_body:
                return {'error': 'Invalid'}
            body = c
            seen_body = True
        elif seen_body:
            if version == 12:
                return {'error': 'Invalid'}
        else:
            return {'error': 'Invalid'}
    if body is None:
        return {'error': 'Invalid'}
    out = {'error': 'ok', 'version': version, 'header': header is not None}
    payload = next(iter(body), None)
    out['payload'] = qn(payload.tag) if payload is not None else None
    out['fault'] = payload is not None and qn(payload.tag) == (uri, 'Fault')
    out['must'] = []
    if header is not None:
        for blk in header:
            for attr, value in blk.attrib.items():
                au, al = qn(attr)
                if au == uri and al == 'mustUnderstand' and value in ('1', 'true'):
                    out['must'].append(qn(blk.tag)[1])
    if out['fault']:
        out['fault_info'] = fault_info(payload, uri, version, nsmap)
    return out


def code_of(raw, version, nsmap):
    raw = raw.strip()
    prefix, _, local = raw.rpartition(':')
    uri = nsmap.get(prefix) if prefix else nsmap.get('')
    if uri is None and prefix:
        return 'unbound', raw
    uri = uri or ''
    ns = NS11 if version == 11 else NS12
    if uri != ns:
        return 'Other', raw
    table = {'VersionMismatch': 'VersionMismatch', 'MustUnderstand': 'MustUnderstand'}
    if version == 12:
        table.update({'DataEncodingUnknown': 'DataEncodingUnknown', 'Sender': 'Sender', 'Receiver': 'Receiver'})
    else:
        table.update({'Client': 'Sender', 'Server': 'Receiver'})
    return table.get(local, 'Other'), raw


def text_of(el):
    return ''.join(el.itertext()) if el is not None else ''


def fault_info(f, uri, version, nsmap):
    info = {'actor': '', 'detail': False, 'subcode': '', 'language': ''}
    if version == 11:
        code = f.find('faultcode')
        reason = f.find('faultstring')
        if code is None or reason is None:
            info['error'] = 'Invalid'
            return info
        info['code'], info['code_text'] = code_of(text_of(code), 11, nsmap)
        info['reason'] = text_of(reason)
        info['actor'] = text_of(f.find('faultactor'))
        info['detail'] = f.find('detail') is not None
    else:
        code = f.find('{%s}Code' % uri)
        reason = f.find('{%s}Reason' % uri)
        value = code.find('{%s}Value' % uri) if code is not None else None
        text = reason.find('{%s}Text' % uri) if reason is not None else None
        if code is None or reason is None or value is None or text is None:
            info['error'] = 'Invalid'
            return info
        info['code'], info['code_text'] = code_of(text_of(value), 12, nsmap)
        sub = code.find('{%s}Subcode' % uri)
        if sub is not None and sub.find('{%s}Value' % uri) is not None:
            info['subcode'] = text_of(sub.find('{%s}Value' % uri)).strip()
        info['reason'] = text_of(text)
        info['language'] = text.attrib.get('{http://www.w3.org/XML/1998/namespace}lang', '')
        info['actor'] = text_of(f.find('{%s}Role' % uri))
        info['detail'] = f.find('{%s}Detail' % uri) is not None
    info['error'] = 'ok'
    return info


E11 = 'xmlns:s="%s"' % NS11
E12 = 'xmlns:s="%s"' % NS12
docs = [
    ('req11', '<s:Envelope %s><s:Header><t:Trans xmlns:t="urn:t" s:mustUnderstand="1">5</t:Trans><t:Other xmlns:t="urn:t" s:mustUnderstand="0"/></s:Header><s:Body><m:GetPrice xmlns:m="urn:prices"><m:Item>Apples</m:Item></m:GetPrice></s:Body></s:Envelope>' % E11),
    ('resp11', '<s:Envelope %s><s:Body><m:GetPriceResponse xmlns:m="urn:prices"><m:Price>1.5</m:Price></m:GetPriceResponse></s:Body></s:Envelope>' % E11),
    ('fault11', '<s:Envelope %s><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>Bad  input &amp; more</faultstring><faultactor>http://x.example/actor</faultactor><detail><e:Err xmlns:e="urn:e">42</e:Err></detail></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-server', '<s:Envelope %s><s:Body><s:Fault><faultcode>s:Server</faultcode><faultstring>down</faultstring></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-vm', '<s:Envelope %s><s:Body><s:Fault><faultcode>s:VersionMismatch</faultcode><faultstring>v</faultstring></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-mu', '<s:Envelope %s><s:Body><s:Fault><faultcode> s:MustUnderstand </faultcode><faultstring>m</faultstring></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-custom', '<s:Envelope %s xmlns:app="urn:app"><s:Body><s:Fault><faultcode>app:Quota</faultcode><faultstring>q</faultstring></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-dotted', '<s:Envelope %s><s:Body><s:Fault><faultcode>s:Client.Auth</faultcode><faultstring>a</faultstring></s:Fault></s:Body></s:Envelope>' % E11),
    ('fault11-incomplete', '<s:Envelope %s><s:Body><s:Fault><faultcode>s:Client</faultcode></s:Fault></s:Body></s:Envelope>' % E11),
    ('req12', '<env:Envelope xmlns:env="%s"><env:Header><n:alert xmlns:n="urn:n" env:mustUnderstand="true" env:role="http://example.org/r">x</n:alert></env:Header><env:Body><p:Op xmlns:p="urn:p"/></env:Body></env:Envelope>' % NS12),
    ('fault12', '<env:Envelope xmlns:env="%s" xmlns:rpc="http://www.w3.org/2003/05/soap-rpc"><env:Body><env:Fault><env:Code><env:Value>env:Sender</env:Value><env:Subcode><env:Value>rpc:BadArguments</env:Value></env:Subcode></env:Code><env:Reason><env:Text xml:lang="en">Processing error</env:Text><env:Text xml:lang="cs">Chyba</env:Text></env:Reason><env:Role>urn:role</env:Role><env:Detail><e:x xmlns:e="urn:e"/></env:Detail></env:Fault></env:Body></env:Envelope>' % NS12),
    ('fault12-receiver', '<env:Envelope xmlns:env="%s"><env:Body><env:Fault><env:Code><env:Value>env:Receiver</env:Value></env:Code><env:Reason><env:Text>boom</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>' % NS12),
    ('fault12-dataenc', '<env:Envelope xmlns:env="%s"><env:Body><env:Fault><env:Code><env:Value>env:DataEncodingUnknown</env:Value></env:Code><env:Reason><env:Text xml:lang="de">k</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>' % NS12),
    ('fault12-client-is-other', '<env:Envelope xmlns:env="%s"><env:Body><env:Fault><env:Code><env:Value>env:Client</env:Value></env:Code><env:Reason><env:Text>c</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>' % NS12),
    ('fault12-incomplete', '<env:Envelope xmlns:env="%s"><env:Body><env:Fault><env:Code><env:Value>env:Sender</env:Value></env:Code></env:Fault></env:Body></env:Envelope>' % NS12),
    ('prefix-soapenv', '<SOAP-ENV:Envelope xmlns:SOAP-ENV="%s"><SOAP-ENV:Body><x:Y xmlns:x="urn:x"/></SOAP-ENV:Body></SOAP-ENV:Envelope>' % NS11),
    ('default-ns', '<Envelope xmlns="%s"><Header/><Body><Ping xmlns="urn:ping"/></Body></Envelope>' % NS11),
    ('empty-body', '<s:Envelope %s><s:Body/></s:Envelope>' % E11),
    ('comments-and-space', '<s:Envelope %s>\n <!-- c -->\n <s:Body>\n  <m:Q xmlns:m="urn:q"/>\n </s:Body>\n</s:Envelope>' % E11),
    ('trailing11', '<s:Envelope %s><s:Body><m:Q xmlns:m="urn:q"/></s:Body><x:Extra xmlns:x="urn:x"/></s:Envelope>' % E11),
    ('trailing12', '<s:Envelope %s><s:Body><m:Q xmlns:m="urn:q"/></s:Body><x:Extra xmlns:x="urn:x"/></s:Envelope>' % E12),
    ('mu-wrong-ns', '<s:Envelope %s><s:Header><t:T xmlns:t="urn:t" xmlns:o="urn:other" o:mustUnderstand="1"/></s:Header><s:Body/></s:Envelope>' % E11),
    ('two-must', '<s:Envelope %s><s:Header><a:A xmlns:a="urn:a" s:mustUnderstand="1"/><a:B xmlns:a="urn:a" s:mustUnderstand="true"/><a:C xmlns:a="urn:a"/></s:Header><s:Body/></s:Envelope>' % E11),
    ('version-mismatch', '<s:Envelope xmlns:s="http://example.org/soap/9"><s:Body/></s:Envelope>'),
    ('not-soap', '<html><body>hi</body></html>'),
    ('wrong-root-ns', '<s:Envelopes %s><s:Body/></s:Envelopes>' % E11),
    ('missing-body', '<s:Envelope %s><s:Header/></s:Envelope>' % E11),
    ('duplicate-body', '<s:Envelope %s><s:Body/><s:Body/></s:Envelope>' % E11),
    ('header-after-body', '<s:Envelope %s><s:Body/><s:Header/></s:Envelope>' % E11),
    ('two-headers', '<s:Envelope %s><s:Header/><s:Header/><s:Body/></s:Envelope>' % E11),
    ('stray-before-body', '<s:Envelope %s><x:Pre xmlns:x="urn:x"/><s:Body/></s:Envelope>' % E11),
    ('empty-envelope', '<s:Envelope %s/>' % E11),
]
parse_errors = ['<s:Envelope', '<a><b></a>', '', '<s:Envelope xmlns:s="x"><s:Body></s:Envelope>']

L = []


def emit(s):
    L.append(s)


def report_if(cond, table, idx):
    emit('    if %s { try report("%s", %s) }' % (cond, table, idx))


emit('    let ns11 = soap.namespace(.Soap11)')
emit('    let ns12 = soap.namespace(.Soap12)')
report_if('!same(ns11, "%s") || !same(ns12, "%s")' % (NS11, NS12), 'namespaces', '0usize')
parsed = 0
for k, (label, text) in enumerate(docs):
    want = analyse(text)
    emit('    let doc_%d = %s' % (k, quote(text)))
    emit('    let (env_%d, err_%d) = soap.parse(a, doc_%d)' % (k, k, k))
    err_name = {'ok': 'ok', 'NotSoap': 'soap.NotSoap', 'VersionMismatch': 'soap.VersionMismatch', 'Invalid': 'soap.Invalid'}[want['error']]
    if want['error'] != 'ok':
        report_if('err_%d != %s' % (k, err_name), 'doc-error-' + label, '%dusize' % k)
        continue
    parsed += 1
    ver = '.Soap11' if want['version'] == 11 else '.Soap12'
    report_if('err_%d != ok || env_%d.version != %s' % (k, k, ver), 'doc-version-' + label, '%dusize' % k)
    report_if('(env_%d.header != 4294967295u32) != %s' % (k, 'true' if want['header'] else 'false'), 'doc-header-' + label, '%dusize' % k)
    emit('    let payload_%d = soap.payload(&env_%d)' % (k, k))
    if want['payload'] is None:
        report_if('payload_%d != 4294967295u32' % k, 'doc-payload-' + label, '%dusize' % k)
    else:
        uri, local = want['payload']
        emit('    let (pu_%d, pl_%d, pe_%d) = soap.expand(&env_%d.document, payload_%d)' % ((k,) * 5))
        report_if('payload_%d == 4294967295u32 || pe_%d != ok || !same(pu_%d, %s) || !same(pl_%d, %s)' % (k, k, k, quote(uri), k, quote(local)), 'doc-payload-' + label, '%dusize' % k)
    report_if('soap.is_fault(&env_%d) != %s' % (k, 'true' if want['fault'] else 'false'), 'doc-isfault-' + label, '%dusize' % k)
    emit('    var must_ids_%d: [8]u32 = zero' % k)
    emit('    let (must_%d, must_error_%d) = soap.must_understand_blocks(a, &env_%d, must_ids_%d[..])' % ((k,) * 4))
    report_if('must_error_%d != ok || must_%d != %dusize' % (k, k, len(want['must'])), 'doc-must-' + label, '%dusize' % k)
    for j, name in enumerate(want['must']):
        emit('    let (mu_%d_%d, ml_%d_%d, me_%d_%d) = soap.expand(&env_%d.document, must_ids_%d[%dusize])' % (k, j, k, j, k, j, k, k, j))
        report_if('me_%d_%d != ok || !same(ml_%d_%d, %s)' % (k, j, k, j, quote(name)), 'doc-must-name-' + label, '%dusize' % k)
    if want['fault']:
        info = want['fault_info']
        emit('    let (fault_%d, fault_error_%d) = soap.parse_fault(a, &env_%d)' % (k, k, k))
        if info['error'] != 'ok':
            report_if('fault_error_%d != soap.Invalid' % k, 'fault-invalid-' + label, '%dusize' % k)
        else:
            code_enum = info['code']
            if code_enum == 'unbound':
                report_if('fault_error_%d != soap.Invalid' % k, 'fault-unbound-' + label, '%dusize' % k)
            else:
                report_if('fault_error_%d != ok' % k, 'fault-error-' + label, '%dusize' % k)
                report_if('fault_%d.code != .%s' % (k, code_enum), 'fault-code-' + label, '%dusize' % k)
                report_if('!same(fault_%d.code_text, %s)' % (k, quote(info['code_text'])), 'fault-code-text-' + label, '%dusize' % k)
                report_if('!same(fault_%d.reason, %s)' % (k, quote(info['reason'])), 'fault-reason-' + label, '%dusize' % k)
                report_if('!same(fault_%d.actor, %s)' % (k, quote(info['actor'])), 'fault-actor-' + label, '%dusize' % k)
                report_if('!same(fault_%d.subcode, %s)' % (k, quote(info['subcode'])), 'fault-subcode-' + label, '%dusize' % k)
                report_if('!same(fault_%d.language, %s)' % (k, quote(info['language'])), 'fault-lang-' + label, '%dusize' % k)
                report_if('(fault_%d.detail != 4294967295u32) != %s' % (k, 'true' if info['detail'] else 'false'), 'fault-detail-' + label, '%dusize' % k)
                emit('    let typed_%d = soap.fault_error(fault_%d.code)' % (k, k))
                typed = {'VersionMismatch': 'soap.VersionMismatch', 'MustUnderstand': 'soap.MustUnderstand', 'DataEncodingUnknown': 'soap.DataEncodingUnknown', 'Sender': 'soap.Sender', 'Receiver': 'soap.Receiver', 'Other': 'soap.OtherFault'}[code_enum]
                report_if('typed_%d != %s' % (k, typed), 'fault-typed-' + label, '%dusize' % k)
    else:
        emit('    let (_, not_fault_error_%d) = soap.parse_fault(a, &env_%d)' % (k, k))
        report_if('not_fault_error_%d != soap.Invalid' % k, 'not-a-fault-' + label, '%dusize' % k)

# xml well-formedness failures surface as the xml module's error, not a soap one
for k, text in enumerate(parse_errors):
    emit('    let bad_xml_%d = %s' % (k, quote(text)))
    emit('    let (_, bad_xml_error_%d) = soap.parse(a, bad_xml_%d)' % (k, k))
    report_if('bad_xml_error_%d == ok' % k, 'malformed-xml', '%dusize' % k)

# ---- builder ----
def build(version, prefix, body_xml, header_xml=None, mu=False):
    ns = NS11 if version == 11 else NS12
    s = '<%s:Envelope xmlns:%s="%s">' % (prefix, prefix, ns)
    if header_xml is not None:
        s += '<%s:Header>%s</%s:Header>' % (prefix, header_xml, prefix)
    return s + '<%s:Body>%s</%s:Body></%s:Envelope>' % (prefix, body_xml, prefix, prefix)


def fault11(prefix, code, reason, actor='', detail=''):
    s = '<%s:Fault><faultcode>%s:%s</faultcode><faultstring>%s</faultstring>' % (prefix, prefix, code, reason)
    if actor:
        s += '<faultactor>%s</faultactor>' % actor
    if detail:
        s += '<detail>%s</detail>' % detail
    return s + '</%s:Fault>' % prefix


def fault12(prefix, code, reason, lang='en', subcode='', actor='', detail=''):
    s = '<%s:Fault><%s:Code><%s:Value>%s:%s</%s:Value>' % (prefix, prefix, prefix, prefix, code, prefix)
    if subcode:
        s += '<%s:Subcode><%s:Value>%s</%s:Value></%s:Subcode>' % (prefix, prefix, subcode, prefix, prefix)
    s += '</%s:Code><%s:Reason><%s:Text xml:lang="%s">%s</%s:Text></%s:Reason>' % (prefix, prefix, prefix, lang, reason, prefix, prefix)
    if actor:
        s += '<%s:Role>%s</%s:Role>' % (prefix, actor, prefix)
    if detail:
        s += '<%s:Detail>%s</%s:Detail>' % (prefix, detail, prefix)
    return s + '</%s:Fault>' % prefix


built = [
    ('plain11', build(11, 'soapenv', '<m:Op xmlns:m="urn:m">a &amp; b</m:Op>')),
    ('plain12', build(12, 's', '<m:Op xmlns:m="urn:m"></m:Op>')),
    ('header-mu11', build(11, 's', '<m:Op xmlns:m="urn:m"></m:Op>', '<t:Tx xmlns:t="urn:t" s:mustUnderstand="1">9</t:Tx>')),
    ('header-mu12', build(12, 'env', '<m:Op xmlns:m="urn:m"></m:Op>', '<t:Tx xmlns:t="urn:t" env:mustUnderstand="1">9</t:Tx>')),
    ('f11-client', build(11, 's', fault11('s', 'Client', 'Bad &lt;input&gt;', 'http://actor', 'oops &amp; more'))),
    ('f11-server', build(11, 's', fault11('s', 'Server', 'down'))),
    ('f11-vm', build(11, 's', fault11('s', 'VersionMismatch', 'v'))),
    ('f12-sender', build(12, 's', fault12('s', 'Sender', 'bad', 'en', 'app:Code', 'urn:role', 'why'))),
    ('f12-receiver-de', build(12, 'e', fault12('e', 'Receiver', 'kaputt', 'de'))),
    ('f12-dataenc', build(12, 's', fault12('s', 'DataEncodingUnknown', 'enc'))),
]
for label, text in built:
    ET.fromstring(text)  # well-formed
emit('    var capacity: [4096]u8 = zero')
emit('    var sink_state = io.SliceWriter { data: capacity[..], off: 0usize }')


def builder_block(idx, version, prefix, steps):
    emit('    var sink_%d = io.SliceWriter { data: capacity[..], off: 0usize }' % idx)
    emit('    let (b_%d_made, b_%d_error) = soap.builder(a, io.slice_writer(&sink_%d), %s, "%s")' % (idx, idx, idx, version, prefix))
    emit('    var b_%d = b_%d_made' % (idx, idx))
    emit('    if b_%d_error != ok { try report("builder", %dusize) }' % (idx, idx))
    emit('    var failed_%d = false' % idx)
    for s in steps:
        emit('    if %s != ok { failed_%d = true }' % (s, idx))


def check_output(idx, label, want):
    emit('    if failed_%d || !same(slice_text(&sink_%d), %s) { try report("build-%s", %dusize) }' % (idx, idx, quote(want), label, idx))


# write the expected-output blocks
def body_el(b, attrs, name, text=None, close=True):
    pass


sink_i = 0
tests = [
    ('plain11', '.Soap11', 'soapenv', ['soap.begin(&b_{i})', 'soap.body_start(&b_{i})', 'xml.start(&b_{i}.w, "m:Op", op_attr[..])', 'xml.text(&b_{i}.w, "a & b")', 'xml.end(&b_{i}.w, "m:Op")', 'soap.finish(&b_{i})']),
]
emit('    let op_attr = [1]xml.Attribute{ xml.Attribute { name: "xmlns:m", value: "urn:m" } }')
emit('    let mu_value_attr = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, xml.Attribute { name: "s:mustUnderstand", value: "1" } }')
# 0: plain 1.1
builder_block(0, '.Soap11', 'soapenv', ['soap.begin(&b_0)', 'soap.body_start(&b_0)', 'xml.start(&b_0.w, "m:Op", op_attr[..])', 'xml.text(&b_0.w, "a & b")', 'xml.end(&b_0.w, "m:Op")', 'soap.finish(&b_0)'])
check_output(0, 'plain11', built[0][1])
# 1: plain 1.2, empty element written as start+end
builder_block(1, '.Soap12', 's', ['soap.begin(&b_1)', 'soap.body_start(&b_1)', 'xml.start(&b_1.w, "m:Op", op_attr[..])', 'xml.end(&b_1.w, "m:Op")', 'soap.finish(&b_1)'])
check_output(1, 'plain12', built[1][1])
# 2: header with mustUnderstand via the attribute helper (1.1)
emit('    var mu_made_2: xml.Attribute = zero')
builder_block(2, '.Soap11', 's', ['soap.begin(&b_2)', 'soap.header_start(&b_2)'])
emit('    let (mu_attr_2, mu_attr_error_2) = soap.must_understand_attribute(&b_2)')
emit('    if mu_attr_error_2 != ok || !same(mu_attr_2.name, "s:mustUnderstand") || !same(mu_attr_2.value, "1") { try report("mu-attribute", 2usize) }')
emit('    let mu_attrs_2 = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, mu_attr_2 }')
for s in ['xml.start(&b_2.w, "t:Tx", mu_attrs_2[..])', 'xml.text(&b_2.w, "9")', 'xml.end(&b_2.w, "t:Tx")', 'soap.header_end(&b_2)', 'soap.body_start(&b_2)', 'xml.start(&b_2.w, "m:Op", op_attr[..])', 'xml.end(&b_2.w, "m:Op")', 'soap.finish(&b_2)']:
    emit('    if %s != ok { failed_2 = true }' % s)
check_output(2, 'header-mu11', built[2][1])
# 3: same for 1.2 with prefix env
builder_block(3, '.Soap12', 'env', ['soap.begin(&b_3)', 'soap.header_start(&b_3)'])
emit('    let (mu_attr_3, mu_attr_error_3) = soap.must_understand_attribute(&b_3)')
emit('    let mu_attrs_3 = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, mu_attr_3 }')
for s in ['mu_attr_error_3', 'xml.start(&b_3.w, "t:Tx", mu_attrs_3[..])', 'xml.text(&b_3.w, "9")', 'xml.end(&b_3.w, "t:Tx")', 'soap.header_end(&b_3)', 'soap.body_start(&b_3)', 'xml.start(&b_3.w, "m:Op", op_attr[..])', 'xml.end(&b_3.w, "m:Op")', 'soap.finish(&b_3)']:
    emit('    if %s != ok { failed_3 = true }' % s)
check_output(3, 'header-mu12', built[3][1])
# faults
fault_cases = [
    (4, '.Soap11', 's', 'soap.FaultOut { code: .Sender, reason: "Bad <input>", language: "", actor: "http://actor", detail: "oops & more", subcode: "" }', 'f11-client'),
    (5, '.Soap11', 's', 'soap.FaultOut { code: .Receiver, reason: "down", language: "", actor: "", detail: "", subcode: "" }', 'f11-server'),
    (6, '.Soap11', 's', 'soap.FaultOut { code: .VersionMismatch, reason: "v", language: "", actor: "", detail: "", subcode: "" }', 'f11-vm'),
    (7, '.Soap12', 's', 'soap.FaultOut { code: .Sender, reason: "bad", language: "", actor: "urn:role", detail: "why", subcode: "app:Code" }', 'f12-sender'),
    (8, '.Soap12', 'e', 'soap.FaultOut { code: .Receiver, reason: "kaputt", language: "de", actor: "", detail: "", subcode: "" }', 'f12-receiver-de'),
    (9, '.Soap12', 's', 'soap.FaultOut { code: .DataEncodingUnknown, reason: "enc", language: "", actor: "", detail: "", subcode: "" }', 'f12-dataenc'),
]
for idx, ver, prefix, out, label in fault_cases:
    builder_block(idx, ver, prefix, ['soap.begin(&b_%d)' % idx, 'soap.body_start(&b_%d)' % idx, 'soap.fault_write(&b_%d, %s)' % (idx, out), 'soap.finish(&b_%d)' % idx])
    check_output(idx, label, built[idx][1])
    # the output parses back to the same fault
    emit('    let (round_%d, round_error_%d) = soap.parse(a, slice_text(&sink_%d))' % (idx, idx, idx))
    emit('    if round_error_%d != ok || !soap.is_fault(&round_%d) { try report("build-roundtrip", %dusize) }' % (idx, idx, idx))
    emit('    let (round_fault_%d, round_fault_error_%d) = soap.parse_fault(a, &round_%d)' % (idx, idx, idx))
    emit('    if round_fault_error_%d != ok { try report("build-roundtrip-fault", %dusize) }' % (idx, idx))
# fault refusals
emit('    var sink_x = io.SliceWriter { data: capacity[..], off: 0usize }')
emit('    let (bx_made, bx_error) = soap.builder(a, io.slice_writer(&sink_x), .Soap11, "s")')
emit('    var bx = bx_made')
emit('    if soap.fault_write(&bx, soap.FaultOut { code: .DataEncodingUnknown, reason: "r", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 0usize) }')
emit('    if soap.fault_write(&bx, soap.FaultOut { code: .Other, reason: "r", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 1usize) }')
emit('    if soap.fault_write(&bx, soap.FaultOut { code: .Sender, reason: "", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 2usize) }')
emit('    let (_, empty_prefix_error) = soap.builder(a, io.slice_writer(&sink_x), .Soap11, "")')
emit('    if empty_prefix_error != soap.Invalid { try report("builder-prefix", 0usize) }')
# content types
emit('    let (ct11, ct11_error) = soap.content_type(a, .Soap11, "urn:act")')
emit('    let (ct12, ct12_error) = soap.content_type(a, .Soap12, "urn:act")')
emit('    let (ct12_bare, ct12_bare_error) = soap.content_type(a, .Soap12, "")')
emit('    if ct11_error != ok || ct12_error != ok || ct12_bare_error != ok || !same(ct11, "text/xml; charset=utf-8") || !same(ct12, %s) || !same(ct12_bare, "application/soap+xml; charset=utf-8") { try report("content-type", 0usize) }' % quote('application/soap+xml; charset=utf-8; action="urn:act"'))

# ---- WSDL ----
def wsdl_doc(version, rpc, extra_binding_style=False):
    soap_ns = WSOAP11 if version == 11 else WSOAP12
    style = 'rpc' if rpc else 'document'
    return ('<?xml version="1.0"?><wsdl:definitions xmlns:wsdl="%s" xmlns:soap="%s" xmlns:tns="urn:calc" xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:calc">'
            '<wsdl:message name="AddRequest"><wsdl:part name="a" type="xsd:int"/><wsdl:part name="b" type="xsd:int"/></wsdl:message>'
            '<wsdl:message name="AddResponse"><wsdl:part name="sum" type="xsd:long"/></wsdl:message>'
            '<wsdl:message name="NameRequest"><wsdl:part name="body" element="tns:Name"/></wsdl:message>'
            '<wsdl:message name="NameResponse"><wsdl:part name="body" element="tns:NameReply"/></wsdl:message>'
            '<wsdl:portType name="Calc"><wsdl:operation name="Add"><wsdl:input message="tns:AddRequest"/><wsdl:output message="tns:AddResponse"/></wsdl:operation>'
            '<wsdl:operation name="Name"><wsdl:input message="tns:NameRequest"/><wsdl:output message="tns:NameResponse"/></wsdl:operation>'
            '<wsdl:operation name="Ping"><wsdl:input message="tns:NameRequest"/></wsdl:operation></wsdl:portType>'
            '<wsdl:binding name="CalcBinding" type="tns:Calc"><soap:binding style="%s" transport="http://schemas.xmlsoap.org/soap/http"/>'
            '<wsdl:operation name="Add"><soap:operation soapAction="urn:calc/Add"/></wsdl:operation>'
            '<wsdl:operation name="Name"><soap:operation soapAction="urn:calc/Name" style="%s"/></wsdl:operation></wsdl:binding>'
            '<wsdl:service name="CalcService"><wsdl:port name="CalcPort" binding="tns:CalcBinding"><soap:address location="http://calc.example/soap"/></wsdl:port></wsdl:service>'
            '</wsdl:definitions>') % (WSDL, soap_ns, style, 'document' if rpc else 'rpc')


def wsdl_expect(text):
    tree = ET.fromstring(text)
    uri, local = qn(tree.tag)
    assert (uri, local) == (WSDL, 'definitions')
    msgs = {}
    for m in tree.findall('{%s}message' % WSDL):
        msgs[m.get('name')] = [(p.get('name'), p.get('type') or '', p.get('element') or '') for p in m.findall('{%s}part' % WSDL)]
    ops = []
    for pt in tree.findall('{%s}portType' % WSDL):
        for op in pt.findall('{%s}operation' % WSDL):
            i = op.find('{%s}input' % WSDL)
            o = op.find('{%s}output' % WSDL)
            ops.append({'name': op.get('name'), 'input': (i.get('message').split(':')[-1] if i is not None else ''), 'output': (o.get('message').split(':')[-1] if o is not None else ''), 'action': '', 'style': 'document'})
    soap_version = 11
    for b in tree.findall('{%s}binding' % WSDL):
        default = 'document'
        for ch in b:
            cu, cl = qn(ch.tag)
            if cl == 'binding' and cu in (WSOAP11, WSOAP12):
                default = ch.get('style') or default
                soap_version = 11 if cu == WSOAP11 else 12
            if cu == WSDL and cl == 'operation':
                action, style = '', default
                for inner in ch:
                    iu, il = qn(inner.tag)
                    if il == 'operation' and iu in (WSOAP11, WSOAP12):
                        action = inner.get('soapAction') or ''
                        style = inner.get('style') or style
                for op in ops:
                    if op['name'] == ch.get('name'):
                        op['action'], op['style'] = action, style
    location = ''
    for svc in tree.findall('{%s}service' % WSDL):
        for port in svc:
            for inner in port:
                iu, il = qn(inner.tag)
                if il == 'address' and iu in (WSOAP11, WSOAP12) and not location:
                    location = inner.get('location')
    return {'target': tree.get('targetNamespace') or '', 'location': location, 'version': soap_version, 'ops': ops, 'msgs': msgs}


for w, (version, rpc) in enumerate([(11, False), (12, False), (11, True), (12, True)]):
    text = wsdl_doc(version, rpc)
    want = wsdl_expect(text)
    emit('    let wsdl_%d = %s' % (w, quote(text)))
    emit('    let (wd_%d, wd_error_%d) = soap.wsdl_parse(a, wsdl_%d)' % (w, w, w))
    report_if('wd_error_%d != ok || !same(wd_%d.target_namespace, %s) || !same(wd_%d.location, %s) || wd_%d.soap != %s || wd_%d.operations.len != %dusize' % (
        w, w, quote(want['target']), w, quote(want['location']), w, '.Soap11' if want['version'] == 11 else '.Soap12', w, len(want['ops'])), 'wsdl-header', '%dusize' % w)
    for j, op in enumerate(want['ops']):
        o = 'wd_%d.operations[%dusize]' % (w, j)
        report_if('!same(%s.name, %s) || !same(%s.action, %s) || !same(%s.style, %s) || !same(%s.input, %s) || !same(%s.output, %s)' % (
            o, quote(op['name']), o, quote(op['action']), o, quote(op['style']), o, quote(op['input']), o, quote(op['output'])), 'wsdl-operation', '%dusize' % (w * 10 + j))
        for side, key in (('input_parts', 'input'), ('output_parts', 'output')):
            parts = want['msgs'].get(op[key], [])
            report_if('%s.%s.len != %dusize' % (o, side, len(parts)), 'wsdl-parts-count', '%dusize' % (w * 10 + j))
            for q, (pn, pt, pe) in enumerate(parts):
                p = '%s.%s[%dusize]' % (o, side, q)
                report_if('!same(%s.name, %s) || !same(%s.type_name, %s) || !same(%s.element, %s)' % (p, quote(pn), p, quote(pt), p, quote(pe)), 'wsdl-part', '%dusize' % (w * 10 + j))
emit('    let (wsdl_none, wsdl_none_error) = soap.wsdl_parse(a, "<definitions xmlns=\\"urn:other\\"/>")')
emit('    if wsdl_none_error != soap.Invalid { try report("wsdl-not-wsdl", 0usize) }')
emit('    let (wsdl_empty, wsdl_empty_error) = soap.wsdl_parse(a, "<wsdl:definitions xmlns:wsdl=\\"%s\\" targetNamespace=\\"urn:e\\"/>")' % WSDL)
emit('    if wsdl_empty_error != ok || wsdl_empty.operations.len != 0usize || !same(wsdl_empty.target_namespace, "urn:e") { try report("wsdl-empty", 0usize) }')
emit('    let (wsdl_unnamed, wsdl_unnamed_error) = soap.wsdl_parse(a, "<wsdl:definitions xmlns:wsdl=\\"%s\\"><wsdl:portType name=\\"p\\"><wsdl:operation/></wsdl:portType></wsdl:definitions>")' % WSDL)
emit('    if wsdl_unnamed_error != soap.Invalid { try report("wsdl-unnamed-operation", 0usize) }')

# ---- XSD mapping ----
xsd = {
    'byte': 'i8', 'short': 'i16', 'int': 'i32', 'long': 'i64', 'integer': 'i64', 'nonNegativeInteger': 'i64', 'positiveInteger': 'i64', 'negativeInteger': 'i64',
    'nonPositiveInteger': 'i64', 'unsignedByte': 'u8', 'unsignedShort': 'u16', 'unsignedInt': 'u32', 'unsignedLong': 'u64', 'boolean': 'bool', 'float': 'f32',
    'double': 'f64', 'base64Binary': '[]u8', 'hexBinary': '[]u8', 'string': 'str', 'normalizedString': 'str', 'token': 'str', 'anyURI': 'str', 'QName': 'str',
    'NCName': 'str', 'ID': 'str', 'IDREF': 'str', 'language': 'str', 'Name': 'str', 'NMTOKEN': 'str', 'decimal': 'str', 'dateTime': 'str', 'date': 'str',
    'time': 'str', 'duration': 'str', 'gYear': 'str', 'gYearMonth': 'str', 'gMonth': 'str', 'gMonthDay': 'str', 'gDay': 'str', 'anyType': 'str', 'anySimpleType': 'str',
}
unknown = ['Int', 'STRING', 'xsd:int', '', 'integers', 'unsigned', 'custom', 'Boolean', 'dateTimeStamp']
names = list(xsd) + unknown
emit('    let xsd_names = [%d]str{ %s }' % (len(names), ', '.join(quote(n) for n in names)))
emit('    let xsd_want = [%d]str{ %s }' % (len(names), ', '.join(quote(xsd.get(n, '')) for n in names)))
emit('    var xsd_i = 0usize')
emit('    while xsd_i < %d {' % len(names))
emit('        let (xsd_got, xsd_found) = soap.xsd_neper_type(xsd_names[xsd_i])')
emit('        if xsd_found != (xsd_want[xsd_i].len > 0usize) || !same(xsd_got, xsd_want[xsd_i]) { try report("xsd-type", xsd_i) }')
emit('        xsd_i += 1usize')
emit('    }')
bools = [('true', True, True), ('false', False, True), ('1', True, True), ('0', False, True), (' true ', True, True), ('\\n1\\n', True, True), ('TRUE', False, False), ('yes', False, False), ('', False, False), ('2', False, False), ('tru', False, False)]
for k, (text, value, valid) in enumerate(bools):
    emit('    let (xb_%d, xb_error_%d) = soap.parse_xsd_boolean("%s")' % (k, k, text))
    report_if('(xb_error_%d == ok) != %s || (xb_error_%d == ok && xb_%d != %s)' % (k, 'true' if valid else 'false', k, k, 'true' if value else 'false'), 'xsd-boolean', '%dusize' % k)

body = '\n'.join(L)
source = '''// e.fmt.soap against Python's xml.etree (L080, D2270; scripts/soap_reference.py writes this file): canned
// SOAP 1.1 and 1.2 documents compared with an ElementTree-based reference, the envelope and fault builder
// compared with the reference serialisation and parsed back, canned WSDL 1.1 documents, and the XSD built-in
// type mapping. A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.fmt.soap
use e.fmt.xml

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn slice_text(w: *io.SliceWriter) -> str { ret w.data[..w.off] }

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
    try io.print("soap mismatch in ")
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
    try io.print("fmt soap ok\\n")
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_soap' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote fmt_soap: %d documents (%d parsed), %d built, 4 wsdl, %d xsd names' % (len(docs), parsed, len(built), len(names)))
