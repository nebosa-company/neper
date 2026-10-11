"""Independent oracle for e.algo.rand.fake (L122).

A second implementation of the PCG-XSH-RR-64 style generator and of every generator in
`lib/e/algo/rand/fake.e`, written from the module's documented behaviour, not translated
line by line: it draws bytes, digits and picks in the documented order and builds the
text with Python string formatting and `datetime`. The lookup tables are read from the
Neper source (they are data, one source of truth). `--emit` prints the expected lines
the fixture compares against; run without it, the script checks its own shape rules
(Luhn, RFC 4122 version/variant, IPv4 ranges, calendar dates) over a larger stream.

Usage: python scripts/fake_vectors.py [--emit]
"""
import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / 'lib' / 'e' / 'algo' / 'rand' / 'fake.e').read_text(encoding='utf-8')
M64 = (1 << 64) - 1
MUL = 6364136223846793005


class Pcg:
    def __init__(self, seed, stream):
        self.inc = ((stream << 1) | 1) & M64
        self.state = 0
        self.state = (self.state * MUL + self.inc) & M64
        self.state = (self.state + seed) & M64
        self.state = (self.state * MUL + self.inc) & M64

    def next(self):
        prev = self.state
        self.state = (prev * MUL + self.inc) & M64
        shift = (prev >> 59) + 5
        mixed = ((prev >> shift) ^ prev)
        word = (mixed * 12605985483714917081) & M64
        return ((word >> 43) ^ word) & M64

    def bounded(self, upper):
        if upper == 0:
            return 0
        threshold = ((1 << 64) - upper) % upper
        while True:
            d = self.next()
            if d >= threshold:
                return d % upper


def tables():
    """`fn name(...) -> str { ... ret "a,b" ...}` bodies keyed by function and locale."""
    out = {}
    for m in re.finditer(r'^fn (\w+)\((l: Locale)?\) -> str \{\n(.*?)^\}', SOURCE, re.M | re.S):
        name, has_locale, body = m.group(1), m.group(2), m.group(3)
        if not has_locale:
            out[name] = {None: re.search(r'ret "([^"]*)"', body).group(1)}
            continue
        per = {}
        for c in re.finditer(r'case \.(\w+):\s*ret "([^"]*)"', body):
            per[c.group(1)] = c.group(2)
        per['En'] = re.search(r'default:\s*ret "([^"]*)"', body).group(1)
        out[name] = per
    return out


TABLES = tables()


class Faker:
    def __init__(self, seed, locale):
        self.rng = Pcg(seed, 54)
        self.locale = locale

    def below(self, n):
        return 0 if n == 0 else self.rng.bounded(n)

    def between(self, lo, hi):
        if hi <= lo:
            return lo
        return lo + self.rng.bounded(hi - lo + 1)

    def chance(self, pct):
        return self.below(100) < pct

    def pick(self, table, localized=True):
        t = TABLES[table]
        items = (t[self.locale] if localized else t[None]).split(',')
        return items[self.below(len(items))]

    def digits(self, n):
        return ''.join(str(self.below(10)) for _ in range(n))

    def first(self): return self.pick('first_names')
    def last(self): return self.pick('last_names')
    def city(self): return self.pick('cities')
    def word(self): return self.pick('lorem_words', False)

    def name(self):
        return self.first() + ' ' + self.last()

    def company(self):
        last = self.last()
        return last + ' ' + self.pick('company_suffixes')

    def username(self):
        first = self.first().lower().replace(' ', '')
        last = self.last().lower().replace(' ', '')
        return first + '.' + last + self.digits(2)

    def email(self):
        first = self.first().lower().replace(' ', '')
        last = self.last().lower().replace(' ', '')
        return first + '.' + last + '@' + self.pick('domains', False)

    def address(self):
        number = self.between(1, 199)
        street = self.pick('streets')
        city = self.city()
        head = '%d %s' % (number, street) if self.locale == 'En' else '%s %d' % (street, number)
        return head + ', ' + city

    def phone(self):
        if self.locale == 'De':
            return '+49 ' + self.digits(3) + ' ' + self.digits(8)
        if self.locale == 'Fr':
            return '+33 ' + self.digits(1) + ''.join(' ' + self.digits(2) for _ in range(4))
        if self.locale == 'Es':
            return '+34 ' + self.digits(3) + ''.join(' ' + self.digits(2) for _ in range(3))
        return '+1 ' + self.digits(3) + ' ' + self.digits(3) + ' ' + self.digits(4)

    def uuid4(self):
        raw = bytearray(self.below(256) for _ in range(16))
        raw[6] = (raw[6] & 0x0F) | 0x40
        raw[8] = (raw[8] & 0x3F) | 0x80
        h = raw.hex()
        return '-'.join([h[0:8], h[8:12], h[12:16], h[16:20], h[20:32]])

    def ipv4(self):
        parts = [self.between(1, 223)] + [self.below(256) for _ in range(3)]
        return '.'.join(str(p) for p in parts)

    def mac(self):
        raw = [self.below(256) for _ in range(6)]
        raw[0] = (raw[0] & 0xFC) | 0x02
        return ':'.join('%02x' % v for v in raw)

    def color(self):
        return '#' + ''.join('%02x' % self.below(256) for _ in range(3))

    def card(self):
        digits = '4' + ''.join(str(self.below(10)) for _ in range(14))
        return digits + str(luhn_digit(digits))

    def date(self, lo, hi):
        day = self.between(lo, hi)
        d = datetime.date(1970, 1, 1) + datetime.timedelta(days=day)
        return '%04d-%02d-%02d' % (d.year, d.month, d.day)

    def sentence(self, n):
        words = [self.word() for _ in range(n)]
        if words:
            words[0] = words[0][0].upper() + words[0][1:]
        return ' '.join(words) + '.'

    def paragraph(self, n):
        out = []
        for _ in range(n):
            out.append(self.sentence(self.between(5, 12)))
        return ' '.join(out)


def luhn_digit(payload):
    total = 0
    for i, ch in enumerate(reversed(payload)):
        d = int(ch)
        if i % 2 == 0:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - total % 10) % 10


def luhn_ok(number):
    total = 0
    for i, ch in enumerate(reversed(number)):
        d = int(ch)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


CASES = [(42, 'En'), (7, 'De'), (2024, 'Fr'), (0, 'Es'), (18446744073709551615, 'En')]
ROUNDS = 6


def round_text(f):
    return '|'.join([
        f.name(), f.email(), f.username(), f.company(), f.address(), f.phone(),
        f.uuid4(), f.ipv4(), f.mac(), f.color(), f.card(), f.date(0, 20000),
        f.date(-3000, 3000), f.sentence(6), f.paragraph(2), str(f.between(-5, 5)),
        'y' if f.chance(30) else 'n', f.city(), f.word()])


def emit():
    for seed, loc in CASES:
        f = Faker(seed, loc)
        for _ in range(ROUNDS):
            print(round_text(f))


def shapes():
    f = Faker(99, 'En')
    for _ in range(5000):
        card = f.card()
        assert len(card) == 16 and luhn_ok(card), card
        u = f.uuid4()
        assert re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', u), u
        octets = f.ipv4().split('.')
        assert len(octets) == 4 and all(0 <= int(o) <= 255 for o in octets)
        assert re.fullmatch(r'#[0-9a-f]{6}', f.color())
        assert re.fullmatch(r'[0-9a-f]{2}(:[0-9a-f]{2}){5}', f.mac())
        assert re.fullmatch(r'\d{4}-\d\d-\d\d', f.date(-719000, 2000000))
    print('fake_vectors: shape rules hold over 5000 draws')


if __name__ == '__main__':
    if '--emit' in sys.argv:
        emit()
    else:
        shapes()
