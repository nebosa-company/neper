"""Generate tests/selfhost/fixtures/link/net_robots/src/main.e (L160, D2803).

Reference: the `protego` package (an RFC 9309 robots.txt parser, as used by Scrapy):
`Protego.parse(text).can_fetch(path, agent)`, `.crawl_delay(agent)` and `.sitemaps`.
Random documents use the grammar `e.net.robots` implements (field-name case, comments,
CRLF, spaces around the colon, merged groups, wildcard and `$` patterns, longest-match
priority); queries are paths over a small alphabet against crawler product tokens that
equal group names or are unknown. Avoided on purpose (documented divergences): paths
that need percent normalization beyond hex case, `index.html` rules, and crawler tokens
that merely contain a group name.

    PYTHONPATH=<protego install dir> python scripts/gen_robots_test.py
"""
import random
import sys
from pathlib import Path

from protego import Protego

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(160)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'net_robots' / 'src' / 'main.e'

AGENTS = ['foobot', 'barbot', 'bazbot', 'Googlebot', 'testbot', '*']
CRAWLERS = ['foobot', 'barbot', 'bazbot', 'googlebot', 'testbot', 'unknownbot', 'otherbot']
SEGS = ['a', 'b', 'private', 'public', 'tmp', 'img', 'x1', 'docs', 'search', 'admin', 'p.html', 'q.php', 'file.pdf', 'data', '']
PATH_ENDS = ['', '/', '?q=1', '?id=2&x=3', '.html', '.php', '/index', '.pdf']


def rand_path():
    segs = [random.choice(SEGS) for _ in range(random.randint(0, 3))]
    p = '/' + '/'.join(s for s in segs if s)
    p = p.replace('//', '/')
    p += random.choice(PATH_ENDS)
    while '//' in p:
        p = p.replace('//', '/')
    return p


def rand_pattern():
    base = '/' + '/'.join(random.choice(SEGS[:-1]) for _ in range(random.randint(0, 2)))
    base = base.rstrip('/') or '/'
    r = random.random()
    if r < 0.15:
        base = '/*' + random.choice(['.php', '.pdf', 'tmp', 'x1'])
    elif r < 0.25:
        base = base + '/*/' + random.choice(['a', 'docs', 'img'])
    elif r < 0.3:
        base = '/'
    if random.random() < 0.25:
        base += '$'
    if random.random() < 0.1:
        base = base + '/'
    return base


def render_document():
    lines = []
    ua_count = random.randint(1, 3)
    for _ in range(random.randint(1, 4)):
        group_agents = random.sample(AGENTS, random.randint(1, 2))
        for ag in group_agents:
            name = random.choice(['User-agent', 'user-agent', 'USER-AGENT', 'User-Agent'])
            sep = random.choice([': ', ':', ' : ', ': '])
            lines.append('%s%s%s' % (name, sep, ag) + random.choice(['', '  # comment', '\t']))
        if random.random() < 0.2:
            lines.append('')
        for _ in range(random.randint(0, 5)):
            kind = random.choice(['Allow', 'Disallow', 'Disallow', 'allow', 'DISALLOW'])
            if random.random() < 0.08:
                lines.append('%s:' % kind)
            else:
                lines.append('%s: %s' % (kind, rand_pattern()))
            if random.random() < 0.1:
                lines.append('# note')
        if random.random() < 0.3:
            lines.append('Crawl-delay: %s' % random.choice(['1', '5', '0.5', '10', '2.25', 'abc', '-1', '1.', '30']))
        if random.random() < 0.2:
            lines.append('Sitemap: https://example.com/%s.xml' % random.choice(['a', 'sitemap', 'news']))
        if random.random() < 0.3:
            lines.append('')
    if random.random() < 0.2:
        lines.insert(0, 'Disallow: /orphan')
    nl = random.choice(['\n', '\r\n'])
    return nl.join(lines) + nl


def hx(s):
    return s.encode('utf-8').hex() or '-'


lines = []
docs = 0
while docs < 60:
    text = render_document()
    if 'index.html' in text:
        continue
    pr = Protego.parse(text)
    docs += 1
    queries = []
    for _ in range(14):
        ag = random.choice(CRAWLERS)
        path = rand_path()
        queries.append((ag, path, pr.can_fetch(path, ag)))
    delays = []
    for ag in CRAWLERS:
        d = pr.crawl_delay(ag)
        delays.append((ag, -1 if d is None else int(round(d * 1000))))
    sm = list(pr.sitemaps)
    lines.append('D %s %d %d' % (hx(text), len(queries) + len(delays), len(sm)))
    for ag, path, ok in queries:
        lines.append('Q %s %s %d' % (ag, hx(path), 1 if ok else 0))
    for ag, ms in delays:
        lines.append('C %s %d' % (ag, ms))
    for s in sm:
        lines.append('M %s' % hx(s))
# hand cases with the RFC 9309 examples
rfc = 'User-agent: *\nDisallow: *.gif$\nDisallow: /example/\nAllow: /publications/\n\nUser-agent: foobot\nDisallow:/\nAllow:/example/page.html\nAllow:/example/allowed.gif\n\nUser-agent: barbot\nUser-agent: bazbot\nDisallow: /example/page.html\nDisallow: /\n'
pr = Protego.parse(rfc)
lines.append('D %s %d %d' % (hx(rfc), 9, 0))
for ag, path in (('foobot', '/example/page.html'), ('foobot', '/example/allowed.gif'), ('foobot', '/x'), ('barbot', '/example/page.html'), ('bazbot', '/'),
                 ('otherbot', '/a.gif'), ('otherbot', '/example/z'), ('otherbot', '/publications/x'), ('otherbot', '/robots.txt')):
    lines.append('Q %s %s %d' % (ag, hx(path), 1 if pr.can_fetch(path, ag) else 0))

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

// The checker is stateful: a `D` line parses a document that the `Q`, `C` and `M` lines after
// it query, so the vectors are walked here rather than line by line.
type Ctx = struct { robots: robots.Robots, loaded: bool, sitemap_at: usize }

fn check_line(a: *mem.Arena, c: *Ctx, doc: []u8, line: str) -> u8 {
    var path: [256]u8 = zero
    let (kind, p0) = tok(line, 0usize)
    let k = kind[0usize]
    if k == 68u8 {
        let (h, p1) = tok(line, p0)
        let n = unhex(h, doc[0usize..16384usize])
        let (r, e) = robots.parse(a, doc[0usize..n])
        if e != ok { ret 1u8 }
        c.robots = r
        c.loaded = true
        c.sitemap_at = 0usize
        ret 0u8
    }
    if !c.loaded { ret 2u8 }
    if k == 81u8 {
        let (agent, p1) = tok(line, p0)
        let (h, p2) = tok(line, p1)
        let (want, p3) = tok(line, p2)
        let n = unhex(h, path[0usize..256usize])
        let got = robots.allowed(&c.robots, agent, path[0usize..n])
        if got != (want[0usize] == 49u8) { ret 11u8 }
        ret 0u8
    }
    if k == 67u8 {
        let (agent, p1) = tok(line, p0)
        let (want, p2) = tok(line, p1)
        let (ms, has) = robots.crawl_delay(&c.robots, agent)
        if dec(want) < 0i64 {
            if has { ret 21u8 }
            ret 0u8
        }
        if !has || i64(ms) != dec(want) { ret 22u8 }
        ret 0u8
    }
    // M: the next sitemap
    let (h, p1) = tok(line, p0)
    let n = unhex(h, path[0usize..256usize])
    if c.sitemap_at >= c.robots.sitemaps.len { ret 31u8 }
    if !text_is(c.robots.sitemaps[c.sitemap_at], path[0usize..n]) { ret 32u8 }
    c.sitemap_at += 1usize
    ret 0u8
}

fn run_chunk(a: *mem.Arena, c: *Ctx, doc: []u8, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let code = check_line(a, c, doc, text[start..i])
            if code != 0u8 {
                let shown = io.print(text[start..i])
                ret code
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

'''

calls = '\n'.join('    let r_%s = run_chunk(a, &ctx, doc[0usize..16384usize], %s())\n    if r_%s != 0u8 { os.exit(i32(r_%s)) }' % (n, n, n, n) for n in names)

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    var doc: [16384]u8 = zero
    var ctx: Ctx = zero
''' + calls + '''
    try io.print("net robots ok")
    ret ok
}
'''

src = ('// e.net.robots against the protego package (RFC 9309): random documents with decorated field names,\n'
       '// comments, CRLF, merged groups, wildcard and `$` patterns, and queries for allow/disallow, crawl delay\n'
       '// and sitemaps; plus the RFC 9309 section 5.1 example (D2803). D document, Q query, C crawl delay, M\n'
       '// sitemap. Generated by scripts/gen_robots_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.net.robots\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
