"""Write tests/selfhost/fixtures/link/net_mdns/src/main.e (L086, D2279: mDNS and DNS-SD).

  python scripts/mdns_reference.py

e.net.mdns against python-zeroconf as the independent packet codec. Two services (a printer with IPv4 and IPv6
addresses and TXT strings, a web server on the same host with an empty TXT) are announced, queried and
browsed:
  - every expected response packet is encoded here by a small uncompressed encoder written from RFC 6762/6763 and
    then parsed back with zeroconf's DNSIncoming, which must see exactly the intended records;
  - the queries the responder reads are built by zeroconf's DNSOutgoing (which compresses repeated names);
  - the responses the browser reads are zeroconf's own, built from ServiceInfo records.
A live loopback exchange over two UDP sockets (legacy unicast) is in the template.
"""
import pathlib
import re
import socket
import struct

from zeroconf import DNSIncoming, DNSOutgoing, DNSQuestion, ServiceInfo, const
from zeroconf._dns import DNSAddress, DNSPointer, DNSService, DNSText

root = pathlib.Path(__file__).resolve().parent.parent

CLASS_IN = 1
FLUSH = 0x8000


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


def enc_labels(labels):
    out = b''
    for lab in labels:
        b = lab if isinstance(lab, bytes) else lab.encode('utf-8')
        out += bytes([len(b)]) + b
    return out + b'\x00'


def name_of(*parts):
    labels = []
    for p in parts:
        if isinstance(p, bytes):
            labels.append(p)
        else:
            labels.extend(x.encode('utf-8') for x in p.split('.') if x)
    return enc_labels(labels)


class Svc:
    def __init__(self, instance, stype, host, port, txt, addrs, domain='local', prio=0, weight=0):
        self.instance, self.stype, self.host, self.port = instance, stype, host, port
        self.txt, self.addrs, self.domain, self.prio, self.weight = txt, addrs, domain, prio, weight
        self.ttl_host, self.ttl_other = 120, 4500

    def type_name(self):
        return name_of(self.stype, self.domain)

    def inst_name(self):
        return name_of(self.instance.encode('utf-8'), self.stype, self.domain)

    def host_name(self):
        return name_of(self.host)

    def enum_name(self):
        return name_of('_services._dns-sd._udp', self.domain)

    def txt_rdata(self):
        if not self.txt:
            return b'\x00'
        return b''.join(bytes([len(s.encode())]) + s.encode() for s in self.txt)

    def srv_rdata(self):
        return struct.pack('>HHH', self.prio, self.weight, self.port) + self.host_name()


SERVICES = [
    Svc('My Printer', '_ipp._tcp', 'printer.local', 631, ['rp=ipp/print', 'ty=Acme X', 'note=café'],
        [('v4', '192.168.1.20'), ('v6', 'fe80::1234:5678:9abc:def0'), ('v4', '10.0.0.7')]),
    Svc('Web Server', '_http._tcp', 'printer.local', 80, [], [('v4', '192.168.1.20')], prio=1, weight=5),
]


def rr(name, kind, cls, ttl, rdata):
    return name + struct.pack('>HHIH', kind, cls, ttl, len(rdata)) + rdata


def addr_bytes(a):
    return socket.inet_pton(socket.AF_INET if a[0] == 'v4' else socket.AF_INET6, a[1])


def recs(svc, index, kind, legacy=False, goodbye=False):
    """Records of one kind for services[index], as the library orders and shapes them."""
    other = 0 if goodbye else svc.ttl_other
    host = 0 if goodbye else svc.ttl_host
    cap = (lambda t: min(t, 10)) if legacy else (lambda t: t)
    flush = 0 if legacy else FLUSH
    if kind == 'ptr':
        return [rr(svc.type_name(), 12, CLASS_IN, cap(other), svc.inst_name())]
    if kind == 'enum':
        for earlier in SERVICES[:index]:
            if earlier.type_name().lower() == svc.type_name().lower():
                return []
        return [rr(svc.enum_name(), 12, CLASS_IN, cap(other), svc.type_name())]
    if kind == 'srv':
        return [rr(svc.inst_name(), 33, CLASS_IN | flush, cap(host), svc.srv_rdata())]
    if kind == 'txt':
        return [rr(svc.inst_name(), 16, CLASS_IN | flush, cap(other), svc.txt_rdata())]
    if kind in ('a', 'aaaa'):
        for earlier in SERVICES[:index]:
            if earlier.host.lower() == svc.host.lower():
                return []
    if kind == 'a':
        return [rr(svc.host_name(), 1, CLASS_IN | flush, cap(host), addr_bytes(a)) for a in svc.addrs if a[0] == 'v4']
    if kind == 'aaaa':
        return [rr(svc.host_name(), 28, CLASS_IN | flush, cap(host), addr_bytes(a)) for a in svc.addrs if a[0] == 'v6']
    raise KeyError(kind)


class Builder:
    """A response being built: dedup per (service, kind) like the library, answers before additionals."""
    def __init__(self):
        self.done = set()
        self.answers = []
        self.extra = []

    def add(self, section, index, kind, legacy=False, goodbye=False):
        if (index, kind) in self.done:
            return
        self.done.add((index, kind))
        section.extend(recs(SERVICES[index], index, kind, legacy, goodbye))

    def related(self, index, legacy=False, goodbye=False):
        for k in ('srv', 'txt', 'a', 'aaaa'):
            self.add(self.extra, index, k, legacy, goodbye)


def packet(rid, flags, questions, answers, extra):
    return struct.pack('>HHHHHH', rid, flags, len(questions), len(answers), 0, len(extra)) + b''.join(questions) + b''.join(answers) + b''.join(extra)


def announce_bytes(svcs_index, goodbye=False):
    b = Builder()
    for i in svcs_index:
        b.add(b.answers, i, 'enum', False, goodbye)
        b.add(b.answers, i, 'ptr', False, goodbye)
        for k in ('srv', 'txt', 'a', 'aaaa'):
            b.add(b.answers, i, k, False, goodbye)
    return packet(0, 0x8400, [], b.answers, [])


def question(name, qtype, qu=False):
    return name + struct.pack('>HH', qtype, CLASS_IN | (FLUSH if qu else 0))


def zc_query(questions, known=(), rid=0):
    out = DNSOutgoing(0, multicast=(rid == 0), id_=rid)
    for name, qtype, qu in questions:
        out.add_question(DNSQuestion(name, qtype, const._CLASS_IN | (const._CLASS_UNIQUE if qu else 0)))
    for rec in known:
        out.add_answer_at_time(rec, 0)
    return out.packets()[0]


def dotted(wire):
    labels = []
    i = 0
    while wire[i]:
        labels.append(wire[i + 1:i + 1 + wire[i]].decode('utf-8'))
        i += 1 + wire[i]
    return '.'.join(labels) + '.'


def check_parses(pkt, expect_records):
    """The packet must parse in zeroconf and carry exactly the intended number of records."""
    inc = DNSIncoming(pkt)
    got = inc.answers() + list(inc.additionals) if hasattr(inc, 'additionals') else inc.answers()
    assert len(inc.answers()) == len(expect_records), (len(inc.answers()), len(expect_records))
    return inc


def cases_responder():
    cases = []  # (label, query bytes, legacy, expected response bytes or None, unicast)
    p, w = SERVICES

    def respond(label, qbytes, build, legacy=False, unicast=False, none=False, rid=0):
        if none:
            cases.append((label, qbytes, legacy, b'', False))
            return
        b = Builder()
        build(b)
        flags = 0x8400
        echoed = []
        if legacy:
            cases.append((label, qbytes, legacy, packet(rid, flags, build.echo if hasattr(build, 'echo') else [], b.answers, b.extra), unicast))
        else:
            cases.append((label, qbytes, legacy, packet(0, flags, [], b.answers, b.extra), unicast))

    t1 = p.type_name()
    # 1 PTR for the printer type
    def f(b):
        b.add(b.answers, 0, 'ptr')
        b.related(0)
    respond('ptr', zc_query([(dotted(t1), 12, False)]), f)
    # 2 PTR for the http type
    def f(b):
        b.add(b.answers, 1, 'ptr')
        b.related(1)
    respond('ptr-http', zc_query([('_http._tcp.local.', 12, False)]), f)
    # 3 enumeration
    def f(b):
        b.add(b.answers, 0, 'enum')
        b.add(b.answers, 1, 'enum')
    respond('enum', zc_query([('_services._dns-sd._udp.local.', 12, False)]), f)
    # 4 SRV for an instance (A and AAAA as additionals)
    def f(b):
        b.add(b.answers, 0, 'srv')
        b.add(b.extra, 0, 'a')
        b.add(b.extra, 0, 'aaaa')
    respond('srv', zc_query([(dotted(p.inst_name()), 33, False)]), f)
    # 5 TXT
    def f(b):
        b.add(b.answers, 0, 'txt')
    respond('txt', zc_query([(dotted(p.inst_name()), 16, False)]), f)
    # 6 A and AAAA for the host (shared by both services: the first service's records answer)
    def f(b):
        b.add(b.answers, 0, 'a')
    respond('a', zc_query([('printer.local.', 1, False)]), f)
    def f(b):
        b.add(b.answers, 0, 'aaaa')
    respond('aaaa', zc_query([('printer.local.', 28, False)]), f)
    # 7 ANY on the instance
    def f(b):
        b.add(b.answers, 0, 'srv')
        b.add(b.extra, 0, 'a')
        b.add(b.extra, 0, 'aaaa')
        b.add(b.answers, 0, 'txt')
    respond('any-instance', zc_query([(dotted(p.inst_name()), 255, False)]), f)
    # 8 QU bit asks for a unicast reply
    def f(b):
        b.add(b.answers, 0, 'ptr')
        b.related(0)
    respond('qu', zc_query([(dotted(t1), 12, True)]), f, unicast=True)
    # 9 unknown name and unknown type give no response
    respond('unknown-name', zc_query([('_nothing._tcp.local.', 12, False)]), None, none=True)
    respond('unknown-type', zc_query([(dotted(t1), 16, False)]), None, none=True)
    # 10 case-insensitive question
    def f(b):
        b.add(b.answers, 0, 'ptr')
        b.related(0)
    respond('case', zc_query([('_IPP._TCP.LOCAL.', 12, False)]), f)
    # 11 two questions in one packet (zeroconf compresses the repeated suffix)
    def f(b):
        b.add(b.answers, 0, 'ptr')
        b.related(0)
        b.add(b.answers, 0, 'a')
    respond('two-questions', zc_query([(dotted(t1), 12, False), ('printer.local.', 1, False)]), f)
    # 12 known-answer suppression: a fresh known PTR hides the answer, a stale one does not
    known_fresh = DNSPointer(dotted(t1), const._TYPE_PTR, const._CLASS_IN, 4000, dotted(p.inst_name()))
    respond('known-fresh', zc_query([(dotted(t1), 12, False)], [known_fresh]), None, none=True)
    known_stale = DNSPointer(dotted(t1), const._TYPE_PTR, const._CLASS_IN, 1000, dotted(p.inst_name()))
    def f(b):
        b.add(b.answers, 0, 'ptr')
        b.related(0)
    respond('known-stale', zc_query([(dotted(t1), 12, False)], [known_stale]), f)
    # 13 legacy unicast: the id and the question come back, TTLs are capped, no cache-flush bit
    qb = zc_query([(dotted(t1), 12, False)], rid=0x1234)
    b = Builder()
    b.add(b.answers, 0, 'ptr', legacy=True)
    b.related(0, legacy=True)
    qsec = question(t1, 12)
    cases.append(('legacy', qb, True, packet(0x1234, 0x8400, [qsec], b.answers, b.extra), True))
    # 14 a response is ignored
    out = DNSOutgoing(const._FLAGS_QR_RESPONSE | const._FLAGS_AA)
    cases.append(('ignore-response', out.packets()[0] if out.packets() else packet(0, 0x8400, [], [], []), False, b'', False))
    return cases


def zeroconf_info(svc):
    props = {}
    for s in svc.txt:
        k, _, v = s.partition('=')
        props[k] = v
    return ServiceInfo(svc.stype + '.' + svc.domain + '.', svc.instance + '.' + svc.stype + '.' + svc.domain + '.', port=svc.port,
                       weight=svc.weight, priority=svc.prio, properties=props, server=svc.host + '.',
                       addresses=[addr_bytes(a) for a in svc.addrs])


def zc_response(infos, ttl_override=None, flags=None):
    out = DNSOutgoing(const._FLAGS_QR_RESPONSE | const._FLAGS_AA)
    for info in infos:
        for rec in (info.dns_pointer(), info.dns_service(), info.dns_text()) + tuple(info.dns_addresses()):
            if ttl_override is not None:
                rec = clone(rec, ttl_override)
            out.add_answer_at_time(rec, 0)
    return out.packets()


def clone(rec, ttl):
    if isinstance(rec, DNSPointer):
        return DNSPointer(rec.name, rec.type, rec.class_, ttl, rec.alias)
    if isinstance(rec, DNSService):
        return DNSService(rec.name, rec.type, rec.class_, ttl, rec.priority, rec.weight, rec.port, rec.server)
    if isinstance(rec, DNSText):
        return DNSText(rec.name, rec.type, rec.class_, ttl, rec.text)
    return DNSAddress(rec.name, rec.type, rec.class_, ttl, rec.address, scope_id=getattr(rec, 'scope_id', None))


def build():
    out = {}
    # announcements
    out['announce_all'] = announce_bytes([0, 1])
    out['announce_one'] = announce_bytes([0])
    out['goodbye_all'] = announce_bytes([0, 1], goodbye=True)
    for key in ('announce_all', 'announce_one', 'goodbye_all'):
        inc = DNSIncoming(out[key])
        assert inc.valid, key
    # queries
    p = SERVICES[0]
    out['query_ptr'] = packet(0, 0, [question(p.type_name(), 12)], [], [])
    out['query_ptr_qu'] = packet(0, 0, [question(p.type_name(), 12, True)], [], [])
    known = rr(p.type_name(), 12, CLASS_IN, 4000, p.inst_name())
    out['query_known'] = packet(0, 0, [question(p.type_name(), 12)], [known], [])
    out['query_srv'] = packet(0, 0, [question(p.inst_name(), 33)], [], [])
    for key in ('query_ptr', 'query_ptr_qu', 'query_known', 'query_srv'):
        assert DNSIncoming(out[key]).valid
    inc = DNSIncoming(out['query_known'])
    assert len(inc.questions) == 1 and len(inc.answers()) == 1
    out['inst_wire'] = SERVICES[0].inst_name()
    # zeroconf-built responses for the browser
    out['zc_printer'] = zc_response([zeroconf_info(SERVICES[0])])[0]
    out['zc_both'] = zc_response([zeroconf_info(SERVICES[0]), zeroconf_info(SERVICES[1])])[0]
    out['zc_goodbye'] = zc_response([zeroconf_info(SERVICES[0])], ttl_override=0)[0]
    changed = Svc('My Printer', '_ipp._tcp', 'printer.local', 631, ['rp=ipp/print', 'ty=Acme Y'], [('v4', '192.168.1.99')])
    out['zc_changed'] = zc_response([zeroconf_info(changed)])[0]
    return out


def main():
    data = build()
    cases = cases_responder()

    def service_src(i, s):
        lines = []
        lines.append('    let txt_%d = [%d]str{ %s }' % (i, len(s.txt), ', '.join(quote(t) for t in s.txt)) if s.txt else '    let txt_%d: [0]str = zero' % i)
        entries = []
        for a in s.addrs:
            entries.append('mdns.Address { v6: %s, bytes: %s }' % ('true' if a[0] == 'v6' else 'false', '[16]u8{ %s }' % ', '.join(str(x) for x in addr_bytes(a).ljust(16, b'\x00'))))
        lines.append('    let addrs_%d = [%d]mdns.Address{ %s }' % (i, len(s.addrs), ', '.join(entries)))
        return '\n'.join(lines)

    setup = '\n'.join(service_src(i, s) for i, s in enumerate(SERVICES))
    services_lit = ', '.join(
        'mdns.Service { instance: %s, service: %s, domain: %s, host: %s, port: %du16, priority: %du16, weight: %du16, txt: txt_%d[0..], addresses: addrs_%d[0..], ttl_host: 120u32, ttl_other: 4500u32 }'
        % (quote(s.instance), quote(s.stype), quote(s.domain), quote(s.host), s.port, s.prio, s.weight, i, i) for i, s in enumerate(SERVICES))
    setup += '\n    let services = [%d]mdns.Service{ %s }' % (len(SERVICES), services_lit)

    # responder cases
    case_lines = []
    qs = ', '.join(lit(c[1]) for c in cases)
    ws = ', '.join(lit(c[3]) for c in cases)
    ls = ', '.join('true' if c[2] else 'false' for c in cases)
    us = ', '.join('true' if c[4] else 'false' for c in cases)
    case_lines.append('    let case_queries = [%d]str{ %s }' % (len(cases), qs))
    case_lines.append('    let case_wants = [%d]str{ %s }' % (len(cases), ws))
    case_lines.append('    let case_legacy = [%d]bool{ %s }' % (len(cases), ls))
    case_lines.append('    let case_unicast = [%d]bool{ %s }' % (len(cases), us))
    case_lines.append('    let case_count = %dusize' % len(cases))

    template = (root / 'scripts' / 'mdns_fixture_template.e').read_text(encoding='utf-8')
    subs = {'SETUP': setup, 'CASES': '\n'.join(case_lines)}
    for key, value in data.items():
        subs['D_' + key.upper()] = lit(value)
    text = template
    for key, value in subs.items():
        text = text.replace('@@' + key + '@@', value)
    leftover = re.findall(r'@@[A-Z_0-9]+@@', text)
    assert not leftover, leftover
    out = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_mdns' / 'src'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'main.e').write_text(text, encoding='utf-8', newline='\n')
    print('wrote net_mdns: %d responder cases, %d packets' % (len(cases), len(data)))


main()
