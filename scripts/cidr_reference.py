"""Reference and fixture generator for e.net.cidr (L019).

  python scripts/cidr_reference.py

Answers every case with Python's `ipaddress` module for the arithmetic and its own statement of the refusal order
(the same order the library documents), checks the answers against Terraform's documented examples and against
containment and non-overlap, and writes tests/selfhost/fixtures/link/net_cidr/src/main.e from
scripts/cidr_fixture_template.e. The host bits of a written prefix are ignored (`strict=False`), as in Terraform.
"""
import ipaddress
import pathlib
import random

DIGITS = set('0123456789')


def decimal(text):
    return 1 <= len(text) <= 10 and set(text) <= DIGITS


def parse(prefix):
    """-> (ip_network, None) or (None, error name)."""
    if '/' not in prefix:
        return None, 'BadPrefix'
    addr, length = prefix.split('/', 1)
    if not decimal(length):
        return None, 'BadLength'
    if int(length) > 32:
        return None, 'LengthTooLong'
    fields = addr.split('.')
    bad = False
    for field in fields:
        if not decimal(field):
            return None, 'NotIpv4'
        if int(field) > 255 or (len(field) > 1 and field[0] == '0'):
            bad = True
    if len(fields) != 4 or bad:
        return None, 'BadAddress'
    return ipaddress.ip_network('%s/%s' % (addr, length), strict=False), None


def subnet(prefix, newbits, netnum):
    net, error = parse(prefix)
    if error:
        return 'E:' + error
    if newbits < 0 or netnum < 0:
        return 'E:Negative'
    if newbits > 32 or net.prefixlen + newbits > 32:
        return 'E:NewbitsTooBig'
    if netnum >= 2 ** newbits:
        return 'E:NetnumRange'
    new_length = net.prefixlen + newbits
    start = int(net.network_address) + netnum * 2 ** (32 - new_length)
    sub = ipaddress.ip_network((start, new_length))
    assert sub.subnet_of(net) and sub.network_address in net
    return str(sub)


def host(prefix, hostnum):
    net, error = parse(prefix)
    if error:
        return 'E:' + error
    if hostnum < 0:
        return 'E:Negative'
    if hostnum >= net.num_addresses:
        return 'E:HostRange'
    return str(net.network_address + hostnum)


def netmask(prefix):
    net, error = parse(prefix)
    if error:
        return 'E:' + error
    return str(net.netmask)


def subnets(prefix, newbits):
    net, error = parse(prefix)
    if error:
        return 'E:' + error
    position = 0
    found = []
    for nb in newbits:
        if nb < 0:
            return 'E:Negative'
        if nb > 32 or net.prefixlen + nb > 32:
            return 'E:NewbitsTooBig'
        new_length = net.prefixlen + nb
        size = 2 ** (32 - new_length)
        position = -(-position // size) * size
        if position + size > net.num_addresses:
            return 'E:DoesNotFit'
        found.append(ipaddress.ip_network((int(net.network_address) + position, new_length)))
        position += size
    for i, sub in enumerate(found):
        assert sub.subnet_of(net)
        for other in found[:i]:
            assert not sub.overlaps(other)
    return ','.join(str(s) for s in found)


def check_documented():
    assert subnet('172.16.0.0/12', 4, 2) == '172.18.0.0/16'
    assert subnet('10.1.2.0/24', 4, 15) == '10.1.2.240/28'
    assert subnet('192.168.2.0/20', 4, 6) == '192.168.6.0/24'
    assert host('10.12.127.0/20', 16) == '10.12.112.16'
    assert host('10.12.127.0/20', 268) == '10.12.113.12'
    assert netmask('172.16.0.0/12') == '255.240.0.0'
    assert subnets('10.1.0.0/16', [4, 4, 8, 4]) == '10.1.0.0/20,10.1.16.0/20,10.1.32.0/24,10.1.48.0/20'
    # petcow's tests
    assert subnets('10.0.0.0/16', [8, 8, 8, 4]) == '10.0.0.0/24,10.0.1.0/24,10.0.2.0/24,10.0.16.0/20'
    assert subnet('0.0.0.0/0', 0, 0) == '0.0.0.0/0'
    assert netmask('10.1.0.0/16') == '255.255.0.0' and netmask('10.0.0.0/8') == '255.0.0.0'
    assert host('10.0.0.0/24', 5) == '10.0.0.5' and host('192.168.1.0/24', 0) == '192.168.1.0'
    assert host('10.0.0.0/24', 999) == 'E:HostRange' and host('nope', 1) == 'E:BadPrefix'
    assert subnets('10.0.0.0/30', [8]) == 'E:NewbitsTooBig'
    assert subnets('10.0.0.0/24', [8, 1]) == '10.0.0.0/32,10.0.0.128/25'
    assert subnets('10.0.0.0/24', [1, 1, 1]) == 'E:DoesNotFit'


def lines():
    out = []
    rng = random.Random(1904)
    malformed = ['10.0.0.0', '10.0.0.0/', '/24', '10.0.0.0/33', '10.0.0.0/x', '10.0.0.0/-1', '10.0.0.0/24/1', '10.0.0/24',
                 '10.0.0.256/24', '10.0.0.0.0/24', '10.0..0/24', 'a.b.c.d/24', '::1/64', 'fd00::/8', '10.0.0.010/24',
                 '10.0.0.1/ 24', '999999999999.0.0.0/8', '0.0.0.0/00000000000', '1.2.3.4/032', '', 'nope']
    for m in malformed:
        out.append('P %s => %s' % (m, 'E:' + parse(m)[1] if parse(m)[1] else str(parse(m)[0])))
    good = ['10.0.0.0/8', '10.0.0.5/24', '192.168.1.77/32', '0.0.0.0/0', '255.255.255.255/32', '172.16.0.0/12', '1.2.3.4/0',
            '10.1.2.3/31']
    for g in good:
        net, _ = parse(g)
        out.append('P %s => %s/%d' % (g, g.split('/')[0], net.prefixlen))
    # Terraform's documentation and petcow's tests
    docs = [('172.16.0.0/12', 4, 2), ('10.1.2.0/24', 4, 15), ('192.168.2.0/20', 4, 6), ('0.0.0.0/0', 0, 0), ('10.0.0.5/24', 4, 1),
            ('10.0.0.0/32', 0, 0), ('10.0.0.0/32', 1, 0), ('0.0.0.0/0', 32, 4294967295), ('0.0.0.0/0', 32, 4294967296),
            ('10.0.0.0/24', 8, 255), ('10.0.0.0/24', 8, 256), ('10.0.0.0/24', -1, 0), ('10.0.0.0/24', 2, -1), ('10.0.0.0/24', 33, 0),
            ('10.0.0.0/24', 9, 0), ('10.0.0.0/24', 0, 0), ('10.0.0.0/24', 0, 1), ('255.255.255.0/24', 8, 255), ('10.0.0.0/1', 1, 1)]
    for p, b, n in docs:
        out.append('S %s %d %d => %s' % (p, b, n, subnet(p, b, n)))
    for m in malformed[:8]:
        out.append('S %s 4 1 => %s' % (m, subnet(m, 4, 1)))
    for p, n in (('10.12.127.0/20', 16), ('10.12.127.0/20', 268), ('10.0.0.0/24', 5), ('192.168.1.0/24', 0), ('10.0.0.0/24', 255),
                 ('10.0.0.0/24', 256), ('10.0.0.0/24', 999), ('10.0.0.0/24', -1), ('10.0.0.0/32', 0), ('10.0.0.0/32', 1),
                 ('0.0.0.0/0', 4294967295), ('0.0.0.0/0', 4294967296), ('10.0.0.77/24', 3), ('255.255.255.0/24', 255)):
        out.append('H %s %d => %s' % (p, n, host(p, n)))
    for p in ('172.16.0.0/12', '10.1.0.0/16', '10.0.0.0/8', '0.0.0.0/0', '1.2.3.4/32', '10.0.0.5/31', 'nope', '10.0.0.0/33'):
        out.append('N %s => %s' % (p, netmask(p)))
    for p, bits in (('10.1.0.0/16', [4, 4, 8, 4]), ('10.0.0.0/16', [8, 8, 8, 4]), ('10.0.0.0/30', [8]), ('10.0.0.0/24', [8, 1]),
                    ('10.0.0.0/24', [1, 1]), ('10.0.0.0/24', [1, 1, 1]), ('10.0.0.0/24', [0]), ('10.0.0.0/24', [0, 0]),
                    ('10.0.0.0/24', [-1]), ('10.0.0.0/24', []), ('10.0.0.0/22', [2, 3, 2, 3, 4]), ('0.0.0.0/0', [1, 2, 3, 4]),
                    ('10.0.0.9/24', [2, 2]), ('10.0.0.0/32', [0]), ('10.0.0.0/32', [1])):
        out.append('U %s %s => %s' % (p, ' '.join(map(str, bits)), subnets(p, bits)))
    # seeded random
    for _ in range(150):
        length = rng.randint(0, 32)
        addr = rng.getrandbits(32)
        p = '%s/%d' % (ipaddress.ip_address(addr), length)
        b = rng.choice([rng.randint(0, 32 - length), rng.randint(0, 33), rng.randint(0, 8)])
        n = rng.choice([rng.randrange(0, 2 ** max(b, 0)), rng.randrange(0, 2 ** max(b, 0) + 3), rng.randint(0, 5)])
        out.append('S %s %d %d => %s' % (p, b, n, subnet(p, b, n)))
        h = rng.choice([rng.randrange(0, 2 ** (32 - length)), rng.randrange(0, 2 ** (32 - length) + 3), rng.randint(0, 9)])
        out.append('H %s %d => %s' % (p, h, host(p, h)))
        out.append('N %s => %s' % (p, netmask(p)))
    for _ in range(120):
        length = rng.randint(0, 28)
        p = '%s/%d' % (ipaddress.ip_address(rng.getrandbits(32)), length)
        bits = [rng.randint(0, 6) for _ in range(rng.randint(1, 8))]
        out.append('U %s %s => %s' % (p, ' '.join(map(str, bits)), subnets(p, bits)))
    return out


def main():
    check_documented()
    cases = lines()
    kinds = {}
    for c in cases:
        r = c.split(' => ', 1)[1]
        key = (c[0], r.startswith('E:'))
        kinds[key] = kinds.get(key, 0) + 1
    chunks = ['"' + '\\n'.join(cases[i:i + 70]) + '\\n"' for i in range(0, len(cases), 70)]
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, i + 1) for i in range(len(chunks)))
    here = pathlib.Path(__file__).resolve().parent
    template = (here / 'cidr_fixture_template.e').read_text(encoding='utf-8')
    out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs).replace('    //__VECTOR_CALLS__\n', calls)
    target = here.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_cidr' / 'src' / 'main.e'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8', newline='\n')
    print('wrote', len(cases), 'cases', sorted(kinds.items()))


main()
