"""Independent renderer for e.text.report (L130): the same documented layout drawn on a
character canvas per annotated line (the Neper module builds rows by overwriting a scratch
row; this one places marks and messages on a list-of-lists grid and composes the output
afterwards), over random reports: sources with tabs, accents, CJK and emoji, labels on one
line and across lines, several labels per line, context elision and notes.

Lines: `hex(report json)~hex(expected)`; the fixture decodes the JSON-free fields it needs
from a flat form instead: the report is encoded as
`severity|code|message|name|hex(source)|labels|notes` with labels `start:end:p:message`
joined by `;` and notes `kind=text` joined by `;` (messages and notes are ASCII without
`|`, `;`, `:` or `=`), all fields after `severity` hex-encoded.
"""
import random
import sys


def char_width(cp):
    if cp < 768:
        return 1
    if 768 <= cp <= 879 or cp in (8203, 8204, 8205, 65279) or 65024 <= cp <= 65039:
        return 0
    if 4352 <= cp <= 4447:
        return 2
    if 11904 <= cp <= 42191 and cp != 12351:
        return 2
    for lo, hi in ((44032, 55203), (63744, 64255), (65072, 65135), (65281, 65376), (65504, 65510),
                   (126976, 129791), (131072, 262141)):
        if lo <= cp <= hi:
            return 2
    return 1


def display_width(data, tab):
    text = data.decode('utf-8')
    return sum(tab if ch == '\t' else char_width(ord(ch)) for ch in text)


def expand(text, tab):
    return text.replace('\t', ' ' * tab)


def greedy(text, width):
    spans = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == ' ':
            i += 1
            continue
        j = i
        while j < n and text[j] != ' ':
            j += 1
        spans.append((i, j))
        i = j
    lines = []
    k = 0
    while k < len(spans):
        start, end = spans[k]
        k += 1
        while k < len(spans) and spans[k][1] - start <= width:
            end = spans[k][1]
            k += 1
        lines.append(text[start:end])
    return lines


def render(report, context=1, tab=4, wrap=80):
    src = report['source']  # bytes
    # Lines as byte strings, CR stripped once.
    raw_lines = src.split(b'\n')
    lines = [l[:-1] if l.endswith(b'\r') else l for l in raw_lines]
    starts = []
    pos = 0
    for l in raw_lines:
        starts.append(pos)
        pos += len(l) + 1

    def line_of(off):
        return src[:off].count(b'\n')

    def line_end(n):
        return starts[n] + len(lines[n])

    segments = []  # (line, from, to, primary, message)
    for lab in report['labels']:
        s, e = lab['start'], lab['end']
        first = line_of(s)
        last = line_of(e - 1 if e > s else s)
        fend = line_end(first)
        frm = display_width(src[starts[first]:min(s, fend)], tab) if s <= fend else display_width(src[starts[first]:fend], tab)
        if first == last:
            stop = min(e, fend)
            to = display_width(src[starts[first]:stop], tab) if stop > s else frm + 1
            if to <= frm:
                to = frm + 1
            segments.append((first, frm, to, lab['primary'], lab['message']))
        else:
            line_end_col = display_width(src[starts[first]:fend], tab)
            if line_end_col <= frm:
                line_end_col = frm + 1
            segments.append((first, frm, line_end_col, lab['primary'], ''))
            lstart, lend = starts[last], line_end(last)
            body = src[lstart:lend]
            indent_bytes = len(body) - len(body.lstrip(b' \t'))
            indent = display_width(body[:indent_bytes], tab)
            stop = min(e, lend)
            to = display_width(src[lstart:stop], tab)
            if to <= indent:
                to = indent + 1
            segments.append((last, indent, to, lab['primary'], lab['message']))
    total = len(lines)
    shown = [False] * total
    for seg in segments:
        for k in range(max(0, seg[0] - context), min(total - 1, seg[0] + context) + 1):
            shown[k] = True
    last_shown = max((k for k in range(total) if shown[k]), default=0)
    w = len(str(last_shown + 1))
    out = []
    code = '[%s]' % report['code'] if report['code'] else ''
    out.append('%s%s: %s' % (report['severity'], code, report['message']))
    labels = report['labels']
    if labels:
        anchor = next((l for l in labels if l['primary']), labels[0])
        aline = line_of(anchor['start'])
        acol = display_width(src[starts[aline]:min(anchor['start'], line_end(aline))], 1)
        out.append('%s--> %s:%d:%d' % (' ' * w, report['name'], aline + 1, acol + 1))
        out.append(' ' * w + ' |')
        printed = False
        gap = False
        for n in range(total):
            if not shown[n]:
                gap = True
                continue
            if gap and printed:
                out.append('...')
            gap = False
            printed = True
            out.append('%s | %s' % (str(n + 1).rjust(w), expand(lines[n].decode('utf-8'), tab)))
            on = [s for s in segments if s[0] == n]
            on.sort(key=lambda s: s[1])  # stable: label order among equal starts
            if not on:
                continue
            width = max(s[2] for s in on)
            msgs = [i for i, s in enumerate(on) if s[4]]
            canvas = [[' '] * (width + 2 + max(len(s[4]) for s in on)) for _ in range(1)]
            row = canvas[0]
            for primary_pass in (False, True):
                for s in on:
                    if s[3] == primary_pass:
                        for c in range(s[1], s[2]):
                            row[c] = '^' if s[3] else '-'
            used = width
            inl = msgs[-1] if msgs else None
            if inl is not None:
                text = on[inl][4]
                for t, ch in enumerate(text):
                    row[width + 1 + t] = ch
                used = width + 1 + len(text)
            out.append(' ' * w + ' |' + (' ' + ''.join(row[:used]).rstrip() if ''.join(row[:used]).strip() else ''))
            for j in reversed(msgs):
                if j == inl:
                    continue
                cr = [' '] * len(row)
                for q in range(j + 1):
                    if on[q][4]:
                        cr[on[q][1]] = '|'
                body = ''.join(cr).rstrip()
                out.append(' ' * w + ' |' + (' ' + body if body else ''))
                mr = [' '] * len(row)
                for q in range(j):
                    if on[q][4]:
                        mr[on[q][1]] = '|'
                for t, ch in enumerate(on[j][4]):
                    mr[on[j][1] + t] = ch
                body = ''.join(mr).rstrip()
                out.append(' ' * w + ' |' + (' ' + body if body else ''))
        out.append(' ' * w + ' |')
    for kind, text in report['notes']:
        prefix = w + 3 + len(kind) + 2
        room = wrap - prefix if wrap > prefix + 20 else 20
        wrapped = greedy(text, room)
        head = ' ' * (w + 1) + '= ' + kind + ': '
        if not wrapped:
            out.append(head)
            continue
        for i, ln in enumerate(wrapped):
            out.append((head if i == 0 else ' ' * prefix) + ln)
    return '\n'.join(out) + '\n'


SOURCES = [
    'fn main() {\n    let x = ;\n    let y = 2;\n}\n',
    'let total = price * quantity + tax;\n',
    'a\tb\tc = d\n\tfoo(bar, baz)\n',
    'name = "café 日本語"\nvalue = 10\n',
    'line one\r\nline two\r\nline three\r\nline four\r\nline five\r\nline six\r\nline seven\r\n',
    '{\n  "a": [1, 2,\n    3, 4],\n  "b": null\n}',
    '',
    'x',
    'emoji \U0001F600 here and áccent\n',
]
MESSAGES = ['expected an expression', 'defined here', 'unused', 'this value', 'type mismatch', 'borrowed here', '']
NOTES = [('note', 'a short note'), ('help', 'consider writing a value after the equals sign so that the statement is complete'),
         ('note', 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen'),
         ('help', 'supercalifragilisticexpialidociousandmoretextthatisverylongindeedwithoutanyspacesatall and then words')]


def boundaries(data):
    out = [0]
    for i, b in enumerate(data):
        if i + 1 <= len(data) and (i + 1 == len(data) or (data[i + 1] & 0xC0) != 0x80):
            out.append(i + 1)
    return sorted(set(out))


def make_report(rng):
    src = rng.choice(SOURCES).encode('utf-8')
    bounds = boundaries(src)
    labels = []
    for _ in range(rng.randint(0, 4)):
        a = rng.choice(bounds)
        b = a if rng.random() < 0.15 else rng.choice([x for x in bounds if x >= a])
        if rng.random() < 0.7 and src:
            # keep it on one line mostly
            nl = src.find(b'\n', a)
            if nl != -1 and b > nl:
                b = nl
        labels.append({'start': a, 'end': b, 'message': rng.choice(MESSAGES), 'primary': rng.random() < 0.5})
    if labels and not any(l['primary'] for l in labels) and rng.random() < 0.5:
        labels[0]['primary'] = True
    return {
        'severity': rng.choice(['error', 'warning', 'advice']),
        'code': rng.choice(['', 'E0001', 'W12']),
        'message': rng.choice(['unexpected token', 'unused variable', 'try this']),
        'name': rng.choice(['main.e', 'src/lib.e']),
        'source': src,
        'labels': labels,
        'notes': rng.sample(NOTES, rng.randint(0, 2)),
    }


def encode(report):
    h = lambda s: s.encode('utf-8').hex() if isinstance(s, str) else s.hex()
    labels = ';'.join('%d:%d:%s:%s' % (l['start'], l['end'], 'p' if l['primary'] else 's', h(l['message']))
                      for l in report['labels'])
    notes = ';'.join('%s=%s' % (h(k), h(t)) for k, t in report['notes'])
    sev = {'error': 'e', 'warning': 'w', 'advice': 'a'}[report['severity']]
    return '|'.join([sev, h(report['code']), h(report['message']), h(report['name']), h(report['source']), labels, notes])


def emit():
    rng = random.Random(130)
    return ['%s~%s' % (encode(r), render(r).encode('utf-8').hex()) for r in (make_report(rng) for _ in range(150))]


def selfcheck():
    r = {'severity': 'error', 'code': 'E0001', 'message': 'unexpected token', 'name': 'main.e',
         'source': b'fn main() {\n    let x = ;\n}\n',
         'labels': [{'start': 24, 'end': 25, 'message': 'expected an expression', 'primary': True}],
         'notes': [('help', 'write a value after `=`')]}
    got = render(r)
    want = ('error[E0001]: unexpected token\n'
            ' --> main.e:2:13\n'
            '  |\n'
            '1 | fn main() {\n'
            '2 |     let x = ;\n'
            '  |             ^ expected an expression\n'
            '3 | }\n'
            '  |\n'
            '  = help: write a value after `=`\n')
    assert got == want, got


if __name__ == '__main__':
    selfcheck()
    lines = emit()
    if '--emit' in sys.argv:
        print('\n'.join(lines))
    else:
        print('report_vectors: %d reports' % len(lines))
