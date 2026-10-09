"""Write tests/selfhost/fixtures/link/net_ldap/src/main.e (L085, D2278: the LDAP client).

  python scripts/ldap_reference.py

e.net.ldap against ldap3 (pyasn1 BER) as the independent encoder. About 250 RFC 4515 filter strings, curated and
seeded random, are encoded by ldap3 and the library's `encode_filter` must produce the same bytes. A scripted
conversation (simple, anonymous and SASL PLAIN binds; a search that returns entries, a reference and a done
message; a size-limited search; three compares; add, modify and delete; unbind) is built message by message
with ldap3's operation builders: the bytes the client writes must equal ldap3's requests and the client must
read ldap3's responses (long-form lengths included). A stretch of malformed filters must be Invalid. The
TLS path is exercised by a live StartTLS session against a server thread, written in the template below.
"""
import pathlib
import random
import re

import ldap3
from ldap3.operation.add import add_operation
from ldap3.operation.bind import bind_operation
from ldap3.operation.compare import compare_operation
from ldap3.operation.delete import delete_operation
from ldap3.operation.modify import modify_operation
from ldap3.operation.search import search_operation
from ldap3.protocol import rfc4511 as r
from pyasn1.codec.ber import encoder

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261026)


def lit(data):
    return '"' + ''.join('\\x%02x' % b for b in data) + '"'


def quote(s):
    out = '"'
    for ch in s:
        if ch == '\\':
            out += '\\\\'
        elif ch == '"':
            out += '\\"'
        elif ord(ch) < 32 or ord(ch) > 126:
            for b in ch.encode('utf-8'):
                out += '\\x%02x' % b
        else:
            out += ch
    return out + '"'


# ---- filters ----------------------------------------------------------------------------------------------
FILTERS = [
    '(cn=Ann)', '(cn=*)', '(cn=Ann*)', '(cn=*Ann)', '(cn=*Ann*)', '(cn=A*n*n)', '(cn=a*b*c*d)', '(cn=**)',
    '(cn~=Ann)', '(age>=21)', '(age<=65)', '(&(a=b)(c=d))', '(|(a=b)(c=d)(e=f))', '(!(a=b))', '(&(a=b))',
    '(&(objectClass=person)(|(cn=Ann*)(uid=abc)))', '(!(&(a=*)(b=*)))', '(cn=a\\2ab)', '(cn=\\28paren\\29)',
    '(cn=back\\5cslash)', '(cn=\\00nul)', '(cn=caf\\c3\\a9)', '(cn:dn:2.5.13.5:=Ann)', '(:caseExactMatch:=Ann)',
    '(cn:caseExactMatch:=Ann)', '(:dn:2.4.6.8.10:=Dino)', '(cn:dn:=Ann)', '(cn:2.5.13.2:=Ann)',
    '(cn;lang-en=Ann)', '(2.5.4.3=Ann)', '(userCertificate;binary=*)', '(a=b\\2a*c)',
    '(&(&(a=b)(c=d))(|(e=f)(!(g=h))))', '(|(a=*)(b=*))', '(telephoneNumber=+1 555*)',
    '(mail=a@b.c)', '(uid=a-b_c.d)', '(a=b=c)', '(a=<>)', '(a=b:c)', '(a>=)', '(a=)',
]
ATTRS = ['cn', 'sn', 'uid', 'mail', 'objectClass', 'memberOf', 'givenName', 'a', 'telephoneNumber', 'cn;lang-en']
VALUES = ['x', 'Ann', 'a b', 'caf\\c3\\a9', '42', 'a\\2ab', 'q\\28r\\29', 'path\\5cx', '', 'LongerValue1234', 'z-z', 'a=b']


def rvalue():
    return rnd.choice(VALUES)


def ritem(depth):
    kind = rnd.randint(0, 9)
    a = rnd.choice(ATTRS)
    if kind == 0:
        return '(%s=%s)' % (a, rvalue())
    if kind == 1:
        return '(%s=*)' % a
    if kind == 2:
        parts = [rvalue().replace('', '') for _ in range(rnd.randint(2, 4))]
        return '(%s=%s)' % (a, '*'.join(parts))
    if kind == 3:
        return '(%s~=%s)' % (a, rvalue())
    if kind == 4:
        return '(%s>=%s)' % (a, rvalue())
    if kind == 5:
        return '(%s<=%s)' % (a, rvalue())
    if kind == 6 and depth < 3:
        return '(&%s)' % ''.join(ritem(depth + 1) for _ in range(rnd.randint(1, 3)))
    if kind == 7 and depth < 3:
        return '(|%s)' % ''.join(ritem(depth + 1) for _ in range(rnd.randint(1, 3)))
    if kind == 8 and depth < 3:
        return '(!%s)' % ritem(depth + 1)
    return '(%s=%s*)' % (a, rvalue())


for _ in range(200):
    FILTERS.append(ritem(0))


def filter_bytes(text):
    req = search_operation('dc=x', text, 2, 0, [], 0, 0, False, False, False, None, None, False)
    return encoder.encode(req['filter'])


good = []
for f in FILTERS:
    try:
        b = filter_bytes(f)
        # pyasn1 writes BOOLEAN TRUE as 01, the library (like OpenLDAP) as ff; both are valid BER
        if ':dn' in f.lower() and b.endswith(b'\x84\x01\x01'):
            b = b[:-1] + b'\xff'
        good.append((f, b))
    except Exception:
        continue
# values that ldap3 treats differently from RFC 4515 stay out; an empty value, bare '=', and others are checked above
BAD = ['', '(', ')', '()', '(a)', '(&)', '(|)', '(a=b', 'a=b', '(a=b))', '(=x)', '(a=\\zz)', '(a=\\1)', '(!(a=b)(c=d))', '(a=(b)',
       '(&(a=b)', '(a~b)', '(:=x)', '((a=b))', '(&(a=b)x(c=d))', '(a b=c)', '(a=b)(c=d)', '(!)']

# ---- the scripted conversation ---------------------------------------------------------------------------


def envelope(mid, name, op):
    m = r.LDAPMessage()
    m['messageID'] = r.MessageID(mid)
    m['protocolOp'] = r.ProtocolOp().setComponentByName(name, op)
    return encoder.encode(m)


def result_op(cls, code, matched='', message='', referrals=()):
    op = cls()
    op['resultCode'] = code
    op['matchedDN'] = matched
    op['diagnosticMessage'] = message
    if referrals:
        ref = r.Referral()
        for i, url in enumerate(referrals):
            ref[i] = url
        op['referral'] = ref
    return op


def entry_op(dn, attrs):
    op = r.SearchResultEntry()
    op['object'] = dn
    lst = r.PartialAttributeList()
    for i, (name, vals) in enumerate(attrs):
        pa = r.PartialAttribute()
        pa['type'] = name
        v = r.Vals()
        for j, val in enumerate(vals):
            v[j] = val
        pa['vals'] = v
        lst[i] = pa
    op['attributes'] = lst
    return op


def request(mid, name, op):
    return envelope(mid, name, op)


big = 'x' * 300
steps = []  # (E source lines, request bytes, [response bytes])


def step(code, req, *resp):
    steps.append((code, req, list(resp)))


ADMIN = 'cn=admin,dc=example,dc=org'
# 1 simple bind
step(['    if ldap.bind_simple(&s, %s, "secret") != ok { ret fail(10i32) }' % quote(ADMIN),
      '    if s.last.code != 0u32 { ret fail(11i32) }'],
     request(1, 'bindRequest', bind_operation(3, 'SIMPLE', ADMIN, 'secret')),
     envelope(1, 'bindResponse', result_op(r.BindResponse, 0)))
# 2 SASL PLAIN
step(['    if ldap.bind_plain(&s, "", "alice", "pw") != ok { ret fail(12i32) }'],
     request(2, 'bindRequest', bind_operation(3, 'SASL', '', None, 'PLAIN', b'\x00alice\x00pw')),
     envelope(2, 'bindResponse', result_op(r.BindResponse, 0)))
# 3 anonymous, then a failed bind
step(['    if ldap.bind_anonymous(&s) != ok { ret fail(13i32) }'],
     request(3, 'bindRequest', bind_operation(3, 'ANONYMOUS', '', '')),
     envelope(3, 'bindResponse', result_op(r.BindResponse, 0)))
step(['    if ldap.bind_simple(&s, "cn=x", "wrong") != ldap.Rejected || s.last.code != 49u32 || !same(s.last.message, "invalid credentials") || !same(s.last.matched_dn, "dc=example") { ret fail(14i32) }'],
     request(4, 'bindRequest', bind_operation(3, 'SIMPLE', 'cn=x', 'wrong')),
     envelope(4, 'bindResponse', result_op(r.BindResponse, 49, 'dc=example', 'invalid credentials')))
# 4 search with entries, a reference and done
FILT = '(&(objectClass=person)(|(cn=Ann*)(mail=*@example.org)))'
sreq = search_operation('dc=example,dc=org', FILT, 2, 0, ['cn', 'mail'], 10, 5, False, False, False, None, None, False)
step(['    let attrs = [2]str{ "cn", "mail" }',
      '    let (found, search_error) = ldap.search(&s, "dc=example,dc=org", ldap.SCOPE_SUBTREE, %s, attrs[0..], 10u32, 5u32, false)' % quote(FILT),
      '    if search_error != ok || found.len != 2usize || s.references != 1usize { ret fail(15i32) }',
      '    if !same(found[0].dn, "cn=Ann,dc=example,dc=org") || found[0].attributes.len != 2usize || !same(found[0].attributes[0].name, "cn") || found[0].attributes[0].values.len != 2usize || !same(found[0].attributes[0].values[1], "Annie") { ret fail(16i32) }',
      '    let ann_mail = ldap.values_of(found[0], "MAIL")',
      '    if ann_mail.len != 1usize || !same(ann_mail[0], "ann@example.org") || ldap.values_of(found[0], "nothing").len != 0usize { ret fail(17i32) }',
      '    let long_values = ldap.values_of(found[1], "description")',
      '    if !same(found[1].dn, "cn=Bob,dc=example,dc=org") || long_values.len != 1usize || long_values[0].len != 300usize || long_values[0][299] != 120u8 { ret fail(18i32) }',
      '    if !same(ldap.values_of(found[1], "cn")[0], "Bob \\x5c caf\\xc3\\xa9") { ret fail(19i32) }'],
     request(5, 'searchRequest', sreq),
     envelope(5, 'searchResEntry', entry_op('cn=Ann,dc=example,dc=org', [('cn', ['Ann', 'Annie']), ('mail', ['ann@example.org'])])),
     envelope(99, 'searchResEntry', entry_op('cn=Other,dc=example,dc=org', [('cn', ['Skipped'])])),
     envelope(5, 'searchResRef', (lambda: (lambda o: (o.extend(['ldap://other.example.org/dc=example,dc=org']), o)[1])(r.SearchResultReference()))()),
     envelope(5, 'searchResEntry', entry_op('cn=Bob,dc=example,dc=org', [('cn', ['Bob \\ café']), ('description', [big])])),
     envelope(5, 'searchResDone', result_op(r.SearchResultDone, 0)))
# 5 size limit exceeded
sreq2 = search_operation('dc=example,dc=org', '(cn=*)', 1, 0, [], 1, 0, True, False, False, None, None, False)
step(['    let (partial, partial_error) = ldap.search(&s, "dc=example,dc=org", ldap.SCOPE_ONE, "(cn=*)", attrs[..0], 1u32, 0u32, true)',
      '    if partial_error != ldap.Rejected || s.last.code != 4u32 || partial.len != 1usize { ret fail(20i32) }'],
     request(6, 'searchRequest', sreq2).replace(b'\x02\x01\x00\x01\x01\x01', b'\x02\x01\x00\x01\x01\xff'),
     envelope(6, 'searchResEntry', entry_op('cn=Ann,dc=example,dc=org', [('cn', [])])),
     envelope(6, 'searchResDone', result_op(r.SearchResultDone, 4, '', 'size limit exceeded')))
# 6 compares
for mid, code, want, tail in ((7, 6, 'true', 'ok'), (8, 5, 'false', 'ok')):
    step(['    let (c%d, c%d_error) = ldap.compare(&s, "cn=Ann,dc=example,dc=org", "mail", "ann@example.org")' % (mid, mid),
          '    if c%d_error != ok || c%d != %s { ret fail(%di32) }' % (mid, mid, want, 20 + mid)],
         request(mid, 'compareRequest', compare_operation('cn=Ann,dc=example,dc=org', 'mail', 'ann@example.org', False)),
         envelope(mid, 'compareResponse', result_op(r.CompareResponse, code)))
step(['    let (_, c9_error) = ldap.compare(&s, "cn=Nobody", "mail", "x")',
      '    if c9_error != ldap.Rejected || s.last.code != 32u32 || !same(s.last.matched_dn, "dc=example,dc=org") { ret fail(30i32) }'],
     request(9, 'compareRequest', compare_operation('cn=Nobody', 'mail', 'x', False)),
     envelope(9, 'compareResponse', result_op(r.CompareResponse, 32, 'dc=example,dc=org', 'no such object')))
# 7 add, modify, delete
step(['    let add_values = [2]str{ "top", "person" }',
      '    let cn_values = [1]str{ "Carol" }',
      '    let new_attributes = [2]ldap.Attribute{ ldap.Attribute { name: "objectClass", values: add_values[0..] }, ldap.Attribute { name: "cn", values: cn_values[0..] } }',
      '    if ldap.add(&s, "cn=Carol,dc=example,dc=org", new_attributes[0..]) != ok { ret fail(31i32) }'],
     request(10, 'addRequest', add_operation('cn=Carol,dc=example,dc=org', {'objectClass': ['top', 'person'], 'cn': ['Carol']}, False)),
     envelope(10, 'addResponse', result_op(r.AddResponse, 0)))
mreq = modify_operation('cn=Carol,dc=example,dc=org', {'mail': [(ldap3.MODIFY_ADD, ['c@example.org'])], 'description': [(ldap3.MODIFY_REPLACE, ['one', 'two'])], 'phone': [(ldap3.MODIFY_DELETE, [])]}, False)
step(['    let mail_values = [1]str{ "c@example.org" }',
      '    let description_values = [2]str{ "one", "two" }',
      '    let none_values: [0]str = zero',
      '    let changes = [3]ldap.Change{ ldap.Change { operation: ldap.MODIFY_ADD, attribute: "mail", values: mail_values[0..] }, ldap.Change { operation: ldap.MODIFY_REPLACE, attribute: "description", values: description_values[0..] }, ldap.Change { operation: ldap.MODIFY_DELETE, attribute: "phone", values: none_values[0..] } }',
      '    if ldap.modify(&s, "cn=Carol,dc=example,dc=org", changes[0..]) != ok { ret fail(32i32) }'],
     request(11, 'modifyRequest', mreq),
     envelope(11, 'modifyResponse', result_op(r.ModifyResponse, 0)))
step(['    if ldap.delete(&s, "cn=Carol,dc=example,dc=org") != ok { ret fail(33i32) }'],
     request(12, 'delRequest', delete_operation('cn=Carol,dc=example,dc=org')),
     envelope(12, 'delResponse', result_op(r.DelResponse, 0)))
step(['    if ldap.delete(&s, "cn=Gone") != ldap.Rejected || s.last.code != 10u32 || s.last.referrals.len != 2usize || !same(s.last.referrals[1], "ldap://b.example.org/") { ret fail(34i32) }'],
     request(13, 'delRequest', delete_operation('cn=Gone')),
     envelope(13, 'delResponse', result_op(r.DelResponse, 10, '', 'referral', ('ldap://a.example.org/', 'ldap://b.example.org/'))))

unbind_msg = envelope(14, 'unbindRequest', r.UnbindRequest(''))

from ldap3.operation.extended import extended_operation

live_req = [
    request(1, 'extendedReq', extended_operation('1.3.6.1.4.1.1466.20037')),
    request(2, 'bindRequest', bind_operation(3, 'SIMPLE', 'cn=live', 'pw')),
    request(3, 'searchRequest', search_operation('dc=live', '(cn=*)', 2, 0, ['cn'], 0, 0, False, False, False, None, None, False)),
    envelope(4, 'unbindRequest', r.UnbindRequest('')),
]
start_op = result_op(r.ExtendedResponse, 0)
live_resp = [
    envelope(1, 'extendedResp', start_op),
    envelope(2, 'bindResponse', result_op(r.BindResponse, 0)),
    envelope(3, 'searchResEntry', entry_op('cn=L,dc=live', [('cn', ['L'])])) + envelope(3, 'searchResDone', result_op(r.SearchResultDone, 0)),
]

sent = b''.join(s[1] for s in steps)
replies = b''.join(b''.join(s[2]) for s in steps)
code_lines = '\n'.join('\n'.join(s[0]) for s in steps)

# ---- the file ---------------------------------------------------------------------------------------------
n = len(good)
CHUNK = 60
filter_fns = []
filter_calls = []
for k in range(0, n, CHUNK):
    part = good[k:k + CHUNK]
    idx = k // CHUNK
    filter_fns.append('fn filters_%d() -> i32 {\n    let filters = [%d]str{ %s }\n    let wants = [%d]str{ %s }\n    var buf: [1024]u8 = zero\n    var i = 0usize\n    while i < %d {\n        let (n, e) = ldap.encode_filter(buf[0..], filters[i])\n        if e != ok || !same(buf[..n], wants[i]) { ret i32(i) + %d }\n        i += 1usize\n    }\n    ret 0i32\n}\n' % (
        idx, len(part), ', '.join(quote(f) for f, _ in part), len(part), ', '.join(lit(b) for _, b in part), len(part), k + 1))
    filter_calls.append('    let filter_code_%d = filters_%d()\n    if filter_code_%d != 0i32 { ret fail(1000i32 + filter_code_%d) }' % (idx, idx, idx, idx))
filters_src = '\n'.join(filter_fns)
wants_src = '\n'.join(filter_calls)
bad_src = '    let bad = [%d]str{ %s }' % (len(BAD), ', '.join(quote(b) for b in BAD))

template = (root / 'scripts' / 'ldap_fixture_template.e').read_text(encoding='utf-8')
cert = (root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_tls' / 'src' / 'main.e').read_text(encoding='utf-8')


def grab(name):
    return re.search(r'    let %s = (".*")\r?\n' % name, cert).group(1)


text = (template.replace('@@FILTER_FNS@@', filters_src).replace('@@FILTER_CALLS@@', wants_src).replace('@@UNBIND@@', lit(unbind_msg)).replace('@@BAD@@', bad_src)
        .replace('@@REPLIES@@', lit(replies)).replace('@@SENT@@', lit(sent)).replace('@@STEPS@@', code_lines)
        .replace('@@MID@@', grab('mid_der')).replace('@@LEAF@@', grab('leaf_der')).replace('@@KEY@@', grab('leaf_pkcs8'))
        .replace('@@COUNT@@', str(n))
        .replace('@@LIVE_REQ0@@', lit(live_req[0])).replace('@@LIVE_REQ1@@', lit(live_req[1])).replace('@@LIVE_REQ2@@', lit(live_req[2])).replace('@@LIVE_REQ3@@', lit(live_req[3]))
        .replace('@@LIVE_RESP0@@', lit(live_resp[0])).replace('@@LIVE_RESP1@@', lit(live_resp[1])).replace('@@LIVE_RESP2@@', lit(live_resp[2])))
out = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_ldap' / 'src'
out.mkdir(parents=True, exist_ok=True)
(out / 'main.e').write_text(text, encoding='utf-8', newline='\n')
print('wrote net_ldap: %d filters (%d ldap3-refused skipped), %d bad, %d steps, %d bytes sent' % (n, len(FILTERS) - n, len(BAD), len(steps), len(sent)))
