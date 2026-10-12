"""Generates the vector region of tests/selfhost/fixtures/link/debug_report (L149, D2765).

Oracle: sentry-sdk (the Python SDK), for what a Sentry envelope client must produce and parse:
`Dsn` for the DSN fields and default ports, `Auth` for the endpoint URL and the X-Sentry-Auth
header, `Envelope.serialize()` for the envelope bytes of an event (plus an attachment) and
`transport._parse_rate_limits` for X-Sentry-Rate-Limits. Inputs are ASCII (the Neper writer does
not \\u-escape, the SDK does).

    PYTHONPATH=<dir with sentry_sdk> python scripts/gen_debug_report_test.py
"""
import datetime
import sys
from pathlib import Path

import sentry_sdk
from sentry_sdk.envelope import Envelope, Item, PayloadRef
from sentry_sdk.transport import _parse_rate_limits
from sentry_sdk.utils import Dsn

FIXTURE = Path(__file__).resolve().parent.parent / 'tests/selfhost/fixtures/link/debug_report/src/main.e'
CLIENT = 'neper.report/0.1'
NS = 10 ** 9

DSNS = [
    'https://pubkey@o1.ingest.sentry.io/42',
    'https://pubkey:sec@o1.ingest.sentry.io:8443/pre/fix/42',
    'http://k@localhost/7',
    'http://k2@127.0.0.1:9000/relay/1',
]


def lit(s):
    out = []
    for c in s.encode():
        if 32 <= c < 127 and c not in (34, 92):
            out.append(chr(c))
        elif c == 92:
            out.append('\\\\')
        elif c == 34:
            out.append('\\"')
        else:
            out.append('\\x%02X' % c)
    return '"' + ''.join(out) + '"'


def iso(ns):
    sec, rem = divmod(ns, NS)
    t = datetime.datetime.fromtimestamp(sec, datetime.timezone.utc)
    return t.strftime('%Y-%m-%dT%H:%M:%S') + '.%09dZ' % rem


EVENTS = [
    dict(id='0123456789abcdef0123456789abcdef', ts=1760270400 * NS + 123456789, level='info',
         message='hello "world"\n', release='app@1.2.3', env='prod', tags=[('region', 'eu'), ('k', 'v w')],
         exc=None, frames=[], attach=False),
    dict(id='fedcba9876543210fedcba9876543210', ts=1760270460 * NS, level='fatal', message='',
         release='app@1.2.3', env='', tags=[], exc=('Panic', 'index 9 out of range'),
         frames=[(0x401000, 'main.fail', 'src/main.e', 12), (0x401200, 'main.run', 'src/main.e', 40),
                 (0, 'main.main', '', 0)], attach=True),
    dict(id='00000000000000000000000000000001', ts=1760270461 * NS + 5, level='error', message='',
         release='', env='', tags=[], exc=('IoError', 'bad\x01byte \\ and tab\t'), frames=[], attach=False),
]


def build_event(e):
    d = {'event_id': e['id'], 'timestamp': iso(e['ts']), 'platform': 'native', 'level': e['level']}
    if e['message']:
        d['message'] = e['message']
    if e['exc']:
        value = {'type': e['exc'][0], 'value': e['exc'][1]}
        if e['frames']:
            frames = []
            for addr, fn, fl, ln in reversed(e['frames']):
                f = {}
                if fn:
                    f['function'] = fn
                if fl:
                    f['filename'] = fl
                if ln:
                    f['lineno'] = ln
                if addr:
                    f['instruction_addr'] = '0x%x' % addr
                frames.append(f)
            value['stacktrace'] = {'frames': frames}
        d['exception'] = {'values': [value]}
    if e['release']:
        d['release'] = e['release']
    if e['env']:
        d['environment'] = e['env']
    if e['tags']:
        d['tags'] = {k: v for k, v in e['tags']}
    return d


def main():
    out = []
    # --- DSN ---------------------------------------------------------------------------
    out.append('fn gen_dsn(a: *mem.Arena) -> i32 {')
    n = 0
    for text in DSNS:
        d = Dsn(text)
        a = d.to_auth(CLIENT)
        n += 1
        base = 1000 + 10 * n
        out.append('    let (d%d, e%d) = report.parse_dsn(%s)' % (n, n, lit(text)))
        out.append('    if e%d != ok { ret %di32 }' % (n, base))
        out.append('    if !str.eq(d%d.scheme, %s) || !str.eq(d%d.host, %s) || d%d.port != %du16 { ret %di32 }' % (
            n, lit(d.scheme), n, lit(d.host), n, d.port, base + 1))
        out.append('    if !str.eq(d%d.public_key, %s) || !str.eq(d%d.secret_key, %s) || !str.eq(d%d.project_id, %s) || !str.eq(d%d.path, %s) { ret %di32 }' % (
            n, lit(d.public_key), n, lit(d.secret_key or ''), n, lit(d.project_id), n, lit(d.path), base + 2))
        api = a.get_api_url()
        target = '/' + api.split('/', 3)[3]
        out.append('    let (t%d, te%d) = report.envelope_target(a, &d%d)' % (n, n, n))
        out.append('    if te%d != ok || !str.eq(t%d, %s) { ret %di32 }' % (n, n, lit(target), base + 3))
        out.append('    let (h%d, he%d) = report.auth_header(a, &d%d, %s)' % (n, n, n, lit(CLIENT)))
        hdr = a.to_header()
        out.append('    if he%d != ok || !str.eq(h%d, %s) { ret %di32 }' % (n, n, lit(hdr), base + 4))
    bad = ['', 'pubkey@host/1', 'ftp://k@h/1', 'https://@h/1', 'https://k@/1', 'https://k@h', 'https://k@h:0/1', 'https://k@h:99999/1']
    for i, text in enumerate(bad):
        out.append('    let (bd%d, be%d) = report.parse_dsn(%s)' % (i, i, lit(text)))
        out.append('    if be%d != report.Invalid { ret %di32 }' % (i, 1100 + i))
    out.append('    ret 0i32')
    out.append('}')
    out.append('')

    # --- envelopes ---------------------------------------------------------------------
    for k, e in enumerate(EVENTS):
        env = Envelope(headers={'event_id': e['id'], 'sent_at': iso(e['ts'])})
        env.add_event(build_event(e))
        if e['attach']:
            env.add_item(Item(payload=PayloadRef(bytes=b'line1\nline2'), type='attachment',
                              headers={'filename': 'log.txt', 'content_type': 'text/plain'}))
        want = env.serialize().decode()
        out.append('fn gen_envelope_%d(a: *mem.Arena) -> i32 {' % k)
        nf = len(e['frames'])
        out.append('    var frames: [4]debug.Frame = zero')
        for i, (addr, fn, fl, ln) in enumerate(e['frames']):
            out.append('    frames[%d] = debug.Frame { address: %dusize, function: %s, file: %s, line: %du32 }' % (
                i, addr, lit(fn), lit(fl), ln))
        out.append('    var tags: [4]report.Tag = zero')
        for i, (tk, tv) in enumerate(e['tags']):
            out.append('    tags[%d] = report.Tag { key: %s, value: %s }' % (i, lit(tk), lit(tv)))
        exc_t = e['exc'][0] if e['exc'] else ''
        exc_v = e['exc'][1] if e['exc'] else ''
        out.append('    let ev = report.Event { id: %s, timestamp: %di64, level: %s, message: %s, err_type: %s, err_value: %s, frames: frames[0..%d], release: %s, environment: %s, tags: tags[0..%d] }' % (
            lit(e['id']), e['ts'], lit(e['level']), lit(e['message']), lit(exc_t), lit(exc_v), nf, lit(e['release']), lit(e['env']), len(e['tags'])))
        out.append('    let (item, item_error) = report.event_item(a, &ev)')
        out.append('    if item_error != ok { ret %di32 }' % (1200 + 10 * k))
        out.append('    var items: [2]report.Item = zero')
        out.append('    items[0] = item')
        if e['attach']:
            out.append('    items[1] = report.Item { kind: "attachment", content_type: "text/plain", filename: "log.txt", payload: "line1\\nline2" }')
        out.append('    let (bytes_out, envelope_error) = report.envelope(a, ev.id, ev.timestamp, items[0..%d])' % (2 if e['attach'] else 1))
        out.append('    if envelope_error != ok { ret %di32 }' % (1201 + 10 * k))
        out.append('    if !str.eq(bytes_out, %s) { ret %di32 }' % (lit(want), 1202 + 10 * k))
        out.append('    ret 0i32')
        out.append('}')
        out.append('')

    # --- rate limits -------------------------------------------------------------------
    now = datetime.datetime(2026, 10, 12, 12, 0, 0)
    headers = [
        '60:error;transaction:organization, 2700::organization:quota_exceeded',
        '30:error:project',
        'x:error:key',
        '5:session;attachment:org',
        '',
        '10:error:a, 20:error:b',
    ]
    out.append('fn gen_rate_limits() -> i32 {')
    out.append('    var limits: [8]report.Limit = zero')
    for i, h in enumerate(headers):
        got = list(_parse_rate_limits(h, now=now))
        out.append('    let n%d = report.parse_rate_limits(%s, 0i64, limits[0..])' % (i, lit(h)))
        out.append('    if n%d != %dusize { ret %di32 }' % (i, len(got), 1300 + 10 * i))
        for j, (cat, until) in enumerate(got):
            secs = int((until - now).total_seconds())
            out.append('    if !str.eq(limits[%d].category, %s) || limits[%d].until != %di64 { ret %di32 }' % (
                j, lit(cat or ''), j, secs * NS, 1301 + 10 * i + j))
    out.append('    ret 0i32')
    out.append('}')

    text = FIXTURE.read_text(encoding='utf-8')
    b = text.index('// BEGIN generated')
    e = text.index('// END generated')
    text = text[:b] + '// BEGIN generated by scripts/gen_debug_report_test.py (sentry-sdk %s)\n' % sentry_sdk.VERSION + '\n'.join(out) + '\n' + text[e:]
    FIXTURE.write_bytes(text.encode('utf-8'))
    print('wrote', len(out), 'lines for sentry-sdk', sentry_sdk.VERSION)


if __name__ == '__main__':
    sys.exit(main())
