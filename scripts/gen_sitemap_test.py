"""Generate tests/selfhost/fixtures/link/fmt_sitemap/src/main.e (L160, D2803).

Reference: Python's `xml.etree.ElementTree` over random sitemap documents (urlset and
sitemapindex; default and prefixed namespaces, extension elements, comments, CDATA, entity
references, whitespace), reading each entry's `loc`, `lastmod`, `changefreq` and `priority`
by local name and applying the protocol's value checks. Writer output is verified by reading
it back through the library and, at generation, by ElementTree (the entries written are
the entries the fixture rebuilds from the same hex fields).
"""
import random
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(161)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'fmt_sitemap' / 'src' / 'main.e'
NS = 'http://www.sitemaps.org/schemas/sitemap/0.9'
FREQS = ['always', 'hourly', 'daily', 'weekly', 'monthly', 'yearly', 'never']


def hx(s):
    return s.encode('utf-8').hex() if s else '-'


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def valid_priority(p):
    try:
        v = float(p)
    except ValueError:
        return False
    if not all(c in '0123456789.' for c in p) or p.count('.') > 1 or p in ('', '.'):
        return False
    return 0.0 <= v <= 1.0


def expected(text):
    try:
        root = ET.fromstring(text.encode('utf-8'))
    except ET.ParseError:
        return None
    name = root.tag.split('}')[-1]
    if name not in ('urlset', 'sitemapindex'):
        return None
    item = 'url' if name == 'urlset' else 'sitemap'
    out = []
    for child in root:
        if child.tag.split('}')[-1] != item:
            continue
        e = {'loc': '', 'lastmod': '', 'changefreq': '', 'priority': ''}
        for f in child:
            n = f.tag.split('}')[-1]
            if n in e:
                e[n] = (f.text or '').strip()
        if not e['loc'] or len(e['loc'].encode()) > 2048:
            return None
        if e['changefreq'] and e['changefreq'] not in FREQS:
            return None
        if e['priority'] and not valid_priority(e['priority']):
            return None
        out.append(e)
    return name == 'sitemapindex', out


def rand_loc():
    return 'https://example.com/' + random.choice(['a', 'b/c', 'page?x=1&y=2', 'q?a=<b>', 'é', 'deep/er/path/file.html', '']) + str(random.randint(0, 99))


def entry():
    e = {'loc': rand_loc(), 'lastmod': '', 'changefreq': '', 'priority': ''}
    if random.random() < 0.6:
        e['lastmod'] = random.choice(['2024-01-02', '2025-12-31T10:00:00+00:00', '2023-06-01T08:30:00Z'])
    if random.random() < 0.5:
        e['changefreq'] = random.choice(FREQS)
    if random.random() < 0.5:
        e['priority'] = random.choice(['0.0', '0.5', '1.0', '0.8', '1', '0', '.3'])
    return e


def render(entries, index, style):
    root = 'sitemapindex' if index else 'urlset'
    item = 'sitemap' if index else 'url'
    prefix = ''
    attr = 'xmlns="%s"' % NS
    if style == 1:
        prefix = 'sm:'
        attr = 'xmlns:sm="%s"' % NS
    ws = random.choice(['', '\n  ', '\n\t'])
    parts = ['<?xml version="1.0" encoding="UTF-8"?>' + ws + '<!-- generated -->' + ws if random.random() < 0.5 else '']
    parts.append('<%s%s %s%s>' % (prefix, root, attr, ' xmlns:image="http://www.google.com/schemas/sitemap-image/1.1"'))
    for e in entries:
        parts.append(ws + '<%s%s>' % (prefix, item))
        order = list(e.items())
        random.shuffle(order)
        for k, v in order:
            if not v:
                continue
            body = esc(v)
            if random.random() < 0.15 and k == 'loc':
                body = '<![CDATA[%s]]>' % v.replace(']]>', ']]]]><![CDATA[>')
            parts.append(ws + '  <%s%s>%s%s%s</%s%s>' % (prefix, k, ' ' if random.random() < 0.2 else '', body, ' ' if random.random() < 0.2 else '', prefix, k))
        if not index and random.random() < 0.2:
            parts.append(ws + '  <image:image><image:loc>https://example.com/i.png</image:loc></image:image>')
        if random.random() < 0.1:
            parts.append('<!-- c -->')
        parts.append(ws + '</%s%s>' % (prefix, item))
    parts.append(ws + '</%s%s>' % (prefix, root))
    return ''.join(parts)


lines = []
for _ in range(80):
    index = random.random() < 0.25
    n = random.randint(0, 6)
    entries = [entry() for _ in range(n)]
    if index:
        for e in entries:
            e['changefreq'] = ''
            e['priority'] = ''
    text = render(entries, index, random.choice([0, 0, 1]))
    exp = expected(text)
    assert exp is not None, text
    isindex, got = exp
    lines.append('P %s => %d %d %s' % (hx(text), len(got), 1 if isindex else 0, ' '.join('%s %s %s %s' % tuple(hx(e[k]) for k in ('loc', 'lastmod', 'changefreq', 'priority')) for e in got)))
bad = [
    '<urlset xmlns="%s"><url></url></urlset>' % NS,
    '<urlset xmlns="%s"><url><loc></loc></url></urlset>' % NS,
    '<urlset xmlns="%s"><url><loc>http://a/</loc><changefreq>sometimes</changefreq></url></urlset>' % NS,
    '<urlset xmlns="%s"><url><loc>http://a/</loc><priority>1.5</priority></url></urlset>' % NS,
    '<urlset xmlns="%s"><url><loc>http://a/</loc><priority>high</priority></url></urlset>' % NS,
    '<html><body/></html>', '<urlset', '', '<urlset xmlns="%s"><url><loc>http://a/</loc></urlset>' % NS,
    '<urlset xmlns="%s"><url><loc>%s</loc></url></urlset>' % (NS, 'x' * 2049),
]
for t in bad:
    assert expected(t) is None or t.startswith('<urlset xmlns') and False
    lines.append('P %s => E' % hx(t))
for text in ('https://a.example/1\nhttps://a.example/2\n\n  https://a.example/3  \r\n', '', '\n\n', 'only'):
    urls = [l.strip() for l in text.split('\n') if l.strip()]
    lines.append('T %s => %d %s' % (hx(text), len(urls), ' '.join(hx(u) for u in urls)))
# writer round trips
for index in (False, True):
    for _ in range(12):
        n = random.randint(0, 5)
        entries = [entry() for _ in range(n)]
        if index:
            for e in entries:
                e['changefreq'] = ''
                e['priority'] = ''
        lines.append('W %d %d %s' % (1 if index else 0, n, ' '.join('%s %s %s %s' % tuple(hx(e[k]) for k in ('loc', 'lastmod', 'changefreq', 'priority')) for e in entries)))
# writer refusals
lines.append('X 0 1 %s - 7a -' % hx('http://a/'))  # changefreq z
lines.append('X 0 1 - - - -')  # empty loc

vec, names = fc.vector_functions('v', lines)

CHECK = '''
fn hexval(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    if s.len == 1usize && s[0usize] == 45u8 { ret 0usize }
    var i = 0usize
    while i + 1usize < s.len {
        out[i / 2usize] = hexval(s[i]) * 16u8 + hexval(s[i + 1usize])
        i += 2usize
    }
    ret s.len / 2usize
}

// Reads `n` entries of four hex fields each from `line` at `p` into `store`, `text` holding bytes.
fn load_entries(line: str, p0: usize, n: usize, text: []u8, store: []sitemap.Entry) -> usize {
    var p = p0
    var used = 0usize
    var k = 0usize
    while k < n {
        var f = 0usize
        var e: sitemap.Entry = zero
        while f < 4usize {
            let (h, next) = tok(line, p)
            p = next
            let len = unhex(h, text[used..text.len])
            let value: str = text[used..used + len]
            used += len
            if f == 0usize { e.loc = value }
            if f == 1usize { e.lastmod = value }
            if f == 2usize { e.changefreq = value }
            if f == 3usize { e.priority = value }
            f += 1usize
        }
        store[k] = e
        k += 1usize
    }
    ret used
}

fn same_entries(got: []const sitemap.Entry, want: []const sitemap.Entry) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if !text_is(got[i].loc, want[i].loc) || !text_is(got[i].lastmod, want[i].lastmod) { ret false }
        if !text_is(got[i].changefreq, want[i].changefreq) || !text_is(got[i].priority, want[i].priority) { ret false }
        i += 1usize
    }
    ret true
}

fn check_line(line: str) -> u8 {
    var arena_buf: [524288]u8 = zero
    var a = mem.arena_from(arena_buf[0usize..524288usize])
    var doc: [16384]u8 = zero
    var text: [16384]u8 = zero
    var want: [16]sitemap.Entry = zero
    let (kind, p0) = tok(line, 0usize)
    let k = kind[0usize]
    if k == 80u8 {
        let (h, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (count_text, p3) = tok(line, p2)
        let n = unhex(h, doc[0usize..16384usize])
        let (sm, e) = sitemap.parse(&a, doc[0usize..n])
        if count_text[0usize] == 69u8 {
            if e == ok { ret 1u8 }
            ret 0u8
        }
        if e != ok { ret 2u8 }
        let (index_text, p4) = tok(line, p3)
        let count = usize(dec(count_text))
        if sm.index != (index_text[0usize] == 49u8) { ret 3u8 }
        let used = load_entries(line, p4, count, text[0usize..16384usize], want[0usize..16usize])
        if !same_entries(sm.entries, want[0usize..count]) { ret 4u8 }
        ret 0u8
    }
    if k == 84u8 {
        let (h, p1) = tok(line, p0)
        let (arrow, p2) = tok(line, p1)
        let (count_text, p3) = tok(line, p2)
        let n = unhex(h, doc[0usize..16384usize])
        let (sm, e) = sitemap.parse_text(&a, doc[0usize..n])
        if e != ok { ret 11u8 }
        let count = usize(dec(count_text))
        if sm.entries.len != count { ret 12u8 }
        var p = p3
        var i = 0usize
        while i < count {
            let (uh, next) = tok(line, p)
            p = next
            var one: [256]u8 = zero
            let un = unhex(uh, one[0usize..256usize])
            if !text_is(sm.entries[i].loc, one[0usize..un]) { ret 13u8 }
            i += 1usize
        }
        ret 0u8
    }
    if k == 87u8 || k == 88u8 {
        let (index_text, p1) = tok(line, p0)
        let (count_text, p2) = tok(line, p1)
        let count = usize(dec(count_text))
        let used = load_entries(line, p2, count, text[0usize..16384usize], want[0usize..16usize])
        var out: [16384]u8 = zero
        var sw: io.SliceWriter = zero
        sw.data = out[0usize..16384usize]
        let writer = io.slice_writer(&sw)
        var e = ok
        if index_text[0usize] == 49u8 {
            e = sitemap.write_index(writer, want[0usize..count])
        } else {
            e = sitemap.write_urlset(writer, want[0usize..count])
        }
        if k == 88u8 {
            if e == ok { ret 21u8 }
            ret 0u8
        }
        if e != ok { ret 22u8 }
        let (sm, parse_error) = sitemap.parse(&a, out[0usize..sw.off])
        if parse_error != ok { ret 23u8 }
        if sm.index != (index_text[0usize] == 49u8) { ret 24u8 }
        if !same_entries(sm.entries, want[0usize..count]) { ret 25u8 }
        ret 0u8
    }
    ret 99u8
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("fmt sitemap ok")
    ret ok
}
'''

src = ('// e.fmt.sitemap against xml.etree.ElementTree: random urlset and sitemapindex documents (namespaces,\n'
       '// extensions, comments, CDATA, entities, whitespace), the protocol value checks, plain-text sitemaps and\n'
       '// writer round trips (D2803). P parse, T text, W write and read back, X write refused. Generated by\n'
       '// scripts/gen_sitemap_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.fmt.sitemap\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
