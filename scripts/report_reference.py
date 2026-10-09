"""Write tests/selfhost/fixtures/link/ui_report/src/main.e (L089, D2282: the banded report engine).

  python scripts/report_reference.py

e.ui.report is checked against a second implementation of the same specification, written here in Python from the
header comment of lib/e/ui/report.e (not translated from the E code), over about eighty seeded random reports: random
pages, band heights, grouping depth (0 to 3), keep-together and repeat-header flags, page breaks before groups,
wrapping and growing text with every template function, sorted and presorted data. For each report the fixture lays
out the pages and compares the page count, the item count of each page, and a 32-bit FNV-1a hash and the byte length of a canonical
dump of every item. All geometry is in multiples of 0.25 so f32 and f64 agree exactly. A few small reports are also
checked item by item against hand-computed pages in the template.
"""
import math
import pathlib
import random

root = pathlib.Path(__file__).resolve().parent.parent
rnd = random.Random(20261027)

# ---- the specification, in Python -------------------------------------------------------------------------


def wrap_paragraph(para, per_line, out):
    if len(para) == 0:
        out.append('')
        return
    i = 0
    line_start = None
    line_end = 0
    emitted = False
    while i < len(para):
        while i < len(para) and para[i] == ' ':
            i += 1
        if i >= len(para):
            break
        w_start = i
        while i < len(para) and para[i] != ' ':
            i += 1
        w_end = i
        wl = w_end - w_start
        while wl > per_line:
            if line_start is not None:
                out.append(para[line_start:line_end])
                emitted = True
                line_start = None
            out.append(para[w_start:w_start + per_line])
            emitted = True
            w_start += per_line
            wl -= per_line
        if line_start is None:
            line_start, line_end = w_start, w_end
        elif w_end - line_start <= per_line:
            line_end = w_end
        else:
            out.append(para[line_start:line_end])
            emitted = True
            line_start, line_end = w_start, w_end
    if line_start is not None:
        out.append(para[line_start:line_end])
        emitted = True
    if not emitted:
        out.append('')


def fixed_wrap(text, size, width):
    per_line = int(width / (0.5 * size))
    if per_line == 0:
        per_line = 1
    out = []
    p = 0
    while True:
        q = text.find('\n', p)
        if q < 0:
            q = len(text)
        wrap_paragraph(text[p:q], per_line, out)
        if q >= len(text):
            break
        p = q + 1
    return out[:64]


def fmt_fixed(v, decimals):
    negative = v < 0
    m = -v if negative else v
    scale = 10.0 ** decimals
    scaled = int(m * scale + 0.5)
    if scaled == 0:
        negative = False
    whole, frac = (scaled // int(scale), scaled % int(scale)) if decimals else (scaled, 0)
    s = ('-' if negative else '') + str(whole)
    if decimals:
        s += '.' + str(frac).rjust(decimals, '0')
    return s


class Report:
    def __init__(self, page, margins, bands, groups, columns, rows, sort):
        self.pw, self.ph = page
        self.ml, self.mt, self.mr, self.mb = margins
        self.bands, self.groups, self.columns, self.rows, self.sort = bands, groups, columns, rows, sort


def expression(rep, order, scope, body):
    lo, hi, row, row_number, page, pages = scope
    if body == 'PAGE':
        return fmt_fixed(page, 0)
    if body == 'PAGES':
        return fmt_fixed(pages, 0)
    if body == 'ROW':
        return fmt_fixed(row_number, 0)
    for fn in ('SUM', 'AVG', 'MIN', 'MAX', 'COUNT'):
        if body.startswith(fn + '('):
            end = body.index(')')
            field = body[len(fn) + 1:end]
            tail = body[end + 2:] if end + 1 < len(body) and body[end + 1] == ':' else ''
            decimals = int(tail) if tail.isdigit() else (2 if tail == '' else int(''.join(c for c in tail if c.isdigit()) or 0))
            if fn == 'COUNT':
                if field == '':
                    return fmt_fixed(hi - lo, 0)
                if field not in rep.columns:
                    return fmt_fixed(0, 0)
                col = rep.columns.index(field)
                return fmt_fixed(sum(1 for r in range(lo, hi) if rep.rows[order[r]][col][0] != ''), 0)
            if field not in rep.columns:
                total, count, low, high = 0.0, 0, 0.0, 0.0
            else:
                col = rep.columns.index(field)
                total, count, low, high = 0.0, 0, 0.0, 0.0
                for r in range(lo, hi):
                    text, num, numeric = rep.rows[order[r]][col]
                    if numeric:
                        if count == 0:
                            low = high = num
                        low, high = min(low, num), max(high, num)
                        total += num
                        count += 1
            value = total
            if fn == 'AVG':
                value = total / count if count else 0.0
            if fn == 'MIN':
                value = low
            if fn == 'MAX':
                value = high
            return fmt_fixed(value, decimals)
    name, _, spec = body.partition(':')
    if name not in rep.columns or row >= len(order):
        return ''
    text, num, numeric = rep.rows[order[row]][rep.columns.index(name)]
    if numeric and spec:
        digits = ''
        for ch in spec:
            if ch.isdigit():
                digits += ch
            else:
                break
        return fmt_fixed(num, int(digits) if digits else 0)
    return text


def expand(rep, order, scope, template):
    if '[' not in template:
        return template
    out = ''
    p = 0
    while p < len(template):
        if template[p] == '[' and p + 1 < len(template) and template[p + 1] == '[':
            out += '['
            p += 2
        elif template[p] == '[':
            q = template.index(']', p + 1)
            out += expression(rep, order, scope, template[p + 1:q])
            p = q + 1
        else:
            out += template[p]
            p += 1
    return out


class Run:
    def __init__(self, rep):
        self.r = rep
        n = len(rep.rows)
        self.order = list(range(n))
        g = len(rep.groups)
        if rep.sort and g:
            self.order.sort(key=lambda i: tuple(rep.rows[i][rep.columns.index(rep.groups[l]['field'])][0].encode() for l in range(g)))
        self.keycols = [rep.columns.index(x['field']) for x in rep.groups]
        self.n = n
        self.header = next((b for b in rep.bands if b['kind'] == 'PageHeader'), None)
        self.footer = next((b for b in rep.bands if b['kind'] == 'PageFooter'), None)
        self.reserved = (self.header['height'] if self.header else 0) + (self.footer['height'] if self.footer else 0)
        self.starts = [[0] * n for _ in range(g)]
        self.ends = [[0] * n for _ in range(g)]
        for l in range(g):
            begin = 0
            for i in range(n):
                boundary = i == 0 or any(self.key(k, i) != self.key(k, i - 1) for k in range(l + 1))
                if boundary:
                    begin = i
                self.starts[l][i] = begin
            stop = n
            for i in range(n - 1, -1, -1):
                boundary = i + 1 == n or any(self.key(k, i + 1) != self.key(k, i) for k in range(l + 1))
                if boundary:
                    stop = i + 1
                self.ends[l][i] = stop
        self.pages_total = 0

    def key(self, l, i):
        return self.r.rows[self.order[i]][self.keycols[l]][0]

    def scope(self, kind, level, row):
        lo, hi = 0, self.n
        if kind in ('GroupHeader', 'GroupFooter'):
            lo, hi = self.starts[level][row], self.ends[level][row]
        if kind == 'Detail':
            lo, hi = row, row + 1
        return (lo, hi, row, self.row_number, self.page_no, self.pages_total)

    def materialise(self, band, scope, left, top, into):
        height = band['height']
        items = []
        for el in band['elements']:
            if el['kind'] == 'Text':
                text = expand(self.r, self.order, scope, el['text'])
                lines = fixed_wrap(text, el['size'], el['width'])
                shown = len(lines)
                lh = el['size'] * 1.25
                if not el['grow']:
                    fits = int(el['height'] / lh)
                    if fits == 0:
                        fits = 1
                    shown = min(shown, fits)
                else:
                    needed = el['y'] + shown * lh
                    height = max(height, needed)
                if into:
                    if el['border']:
                        bh = el['height']
                        if el['grow']:
                            bh = max(bh, shown * lh)
                        items.append(('R', left + el['x'], top + el['y'], el['width'], bh, '', 0, False, 'L'))
                    for l in range(shown):
                        items.append(('T', left + el['x'], top + el['y'] + l * lh, el['width'], lh, lines[l], el['size'], el['bold'], el['align']))
            elif into:
                items.append((el['kind'][0], left + el['x'], top + el['y'], el['width'], el['height'], '', 0, False, 'L'))
        return height, items

    def begin_page(self):
        r = self.r
        self.page_no += 1
        self.items = []
        self.content_top = r.mt
        self.bottom = r.ph - r.mb
        if self.footer:
            self.bottom -= self.footer['height']
        if self.header:
            h, its = self.materialise(self.header, self.scope('PageHeader', 0, self.cur_row), r.ml, r.mt, True)
            self.items += its
            self.content_top += self.header['height']
        self.y = self.content_top

    def end_page(self):
        r = self.r
        if self.footer:
            top = r.ph - r.mb - self.footer['height']
            h, its = self.materialise(self.footer, self.scope('PageFooter', 0, self.cur_row), r.ml, top, True)
            self.items += its
        self.pages.append((self.page_no, self.items))

    def repeat_headers(self):
        for level in range(min(self.open_levels, len(self.r.groups))):
            if self.r.groups[level]['repeat_header']:
                for band in self.r.bands:
                    if band['kind'] == 'GroupHeader' and band['level'] == level:
                        h, its = self.materialise(band, self.scope('GroupHeader', level, self.cur_row), self.r.ml, self.y, True)
                        self.items += its
                        self.y += h

    def break_page(self, repeat):
        self.end_page()
        self.begin_page()
        if repeat:
            self.repeat_headers()

    def place(self, band, scope, repeat):
        h, _ = self.materialise(band, scope, 0, 0, False)
        if self.y + h > self.bottom and self.y > self.content_top:
            self.break_page(repeat)
        placed, its = self.materialise(band, scope, self.r.ml, self.y, True)
        self.items += its
        self.y += placed

    def bands_height(self, kind, level, row):
        total = 0.0
        for band in self.r.bands:
            if band['kind'] == kind and (kind == 'Detail' or band['level'] == level):
                total += self.materialise(band, self.scope(kind, level, row), 0, 0, False)[0]
        return total

    def group_height(self, level, row):
        total = self.bands_height('GroupHeader', level, row)
        end = self.ends[level][row]
        r = row
        if level + 1 >= len(self.r.groups):
            while r < end:
                total += self.bands_height('Detail', 0, r)
                r += 1
        else:
            while r < end:
                total += self.group_height(level + 1, r)
                r = self.ends[level + 1][r]
        return total + self.bands_height('GroupFooter', level, end - 1)

    def emit_kind(self, kind, level, row, repeat):
        for band in self.r.bands:
            if band['kind'] == kind and (kind in ('Detail', 'ReportHeader', 'ReportFooter') or band['level'] == level):
                self.cur_row = row
                self.place(band, self.scope(kind, level, row), repeat)

    def once(self):
        r = self.r
        n, g = self.n, len(r.groups)
        self.page_no = 0
        self.pages = []
        self.open_levels = 0
        self.row_number = 0
        self.cur_row = 0
        self.begin_page()
        self.emit_kind('ReportHeader', 0, 0, False)
        for i in range(n):
            self.cur_row = i
            level = 0
            if i > 0:
                level = g
                for l in range(g):
                    if self.key(l, i) != self.key(l, i - 1):
                        level = l
                        break
            if i > 0 and level < g:
                close = g
                while close > level:
                    close -= 1
                    self.emit_kind('GroupFooter', close, i - 1, True)
                    self.open_levels = close
            if level < g:
                for lvl in range(level, g):
                    wants = any(b['kind'] == 'GroupHeader' and b['level'] == lvl and b['page_break_before'] for b in r.bands)
                    if wants and self.y > self.content_top:
                        self.break_page(False)
                head_total = sum(self.bands_height('GroupHeader', lvl, i) for lvl in range(level, g))
                first = self.bands_height('Detail', 0, i)
                if self.y + head_total + first > self.bottom and self.y > self.content_top:
                    self.break_page(False)
                for lvl in range(level, g):
                    if r.groups[lvl]['keep_together']:
                        whole = self.group_height(lvl, i)
                        room = r.ph - r.mb - r.mt - self.reserved
                        if self.y + whole > self.bottom and whole <= room and self.y > self.content_top:
                            self.break_page(False)
                            break
                for lvl in range(level, g):
                    self.emit_kind('GroupHeader', lvl, i, True)
                    self.open_levels = lvl + 1
            self.row_number += 1
            self.emit_kind('Detail', 0, i, True)
        if n > 0:
            close = g
            while close > 0:
                close -= 1
                self.emit_kind('GroupFooter', close, n - 1, True)
                self.open_levels = close
        self.emit_kind('ReportFooter', 0, n - 1 if n else 0, True)
        self.end_page()

    def layout(self):
        for p in range(4):
            self.once()
            if len(self.pages) == self.pages_total or p == 3:
                break
            self.pages_total = len(self.pages)
        return self.pages


def f2(v):
    return '%.2f' % v


def dump(pages):
    out = []
    for number, items in pages:
        out.append('P %d' % number)
        for kind, x, y, w, h, text, size, bold, align in items:
            out.append('%s %s %s %s %s %s %s %s %s' % (kind, f2(x), f2(y), f2(w), f2(h), align, f2(size), 'B' if bold else 'N', text))
    return '\n'.join(out) + '\n'


def fnv(text):
    h = 2166136261
    data = text.encode('utf-8')
    for b in data:
        h ^= b
        h = (h * 16777619) % 4294967296
    return h + len(data) * 4294967296


# ---- random reports ---------------------------------------------------------------------------------------
WORDS = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', 'iota', 'kappa', 'lambda', 'mu']
REGIONS = ['north', 'south', 'east', 'west']
KINDS = ['x', 'y', 'z']


def rtext(maxwords):
    return ' '.join(rnd.choice(WORDS) for _ in range(rnd.randint(1, maxwords)))


def make_case(index):
    ngroups = rnd.choice([0, 0, 1, 1, 2, 3])
    columns = ['Region', 'Kind', 'Code', 'Name', 'Amount', 'Qty']
    rows = []
    for _ in range(rnd.randint(0, 40)):
        amount = rnd.randint(-400, 4000) / 4.0
        qty = rnd.randint(0, 50)
        rows.append([(rnd.choice(REGIONS), 0.0, False), (rnd.choice(KINDS), 0.0, False), ('c%d' % rnd.randint(1, 4), 0.0, False),
                     (rtext(rnd.choice([1, 2, 4, 8])), 0.0, False), (fmt_fixed(amount, 2), amount, True), (str(qty), float(qty), True)])
    page = (rnd.choice([200.0, 240.0, 320.0]), rnd.choice([160.0, 200.0, 280.0, 400.0]))
    margins = tuple(rnd.choice([0.0, 8.0, 10.0, 12.0]) for _ in range(4))
    width = page[0] - margins[0] - margins[2]
    groups = [{'field': ['Region', 'Kind', 'Code'][l], 'keep_together': rnd.random() < 0.4, 'repeat_header': rnd.random() < 0.5} for l in range(ngroups)]
    bands = []

    def text_element(x, y, w, text, size=None, grow=False, align='Left', bold=False, border=False, h=None):
        size = size or rnd.choice([8.0, 12.0, 16.0])
        return {'kind': 'Text', 'x': x, 'y': y, 'width': w, 'height': h if h is not None else size * 1.25, 'text': text, 'size': size,
                'bold': bold, 'align': align, 'border': border, 'grow': grow}

    def line_element(y):
        return {'kind': 'Line', 'x': 0.0, 'y': y, 'width': width, 'height': 0.0, 'text': '', 'size': 0.0, 'bold': False, 'align': 'Left', 'border': False, 'grow': False}

    def band(kind, height, elements, level=0, pb=False):
        bands.append({'kind': kind, 'height': height, 'elements': elements, 'level': level, 'page_break_before': pb})

    if rnd.random() < 0.7:
        band('ReportHeader', rnd.choice([20.0, 30.0]), [text_element(0.0, 0.0, width, 'Report [COUNT()] rows total [SUM(Amount)]', 16.0, align='Center', bold=True)])
    if rnd.random() < 0.8:
        band('PageHeader', rnd.choice([12.0, 16.0]), [text_element(0.0, 0.0, width * 0.5, 'Page [PAGE] of [PAGES]', 8.0), line_element(10.0)])
    for l in range(ngroups):
        band('GroupHeader', rnd.choice([12.0, 16.0, 20.0]), [text_element(0.0, 0.0, width, '%s: [%s] ([COUNT()] rows)' % (groups[l]['field'], groups[l]['field']), 12.0, bold=True)], l, rnd.random() < 0.15)
        if rnd.random() < 0.2:
            band('GroupHeader', 8.0, [line_element(4.0)], l)
    detail_elements = [text_element(0.0, 0.0, width * 0.25, '[Code]', 8.0), text_element(width * 0.25, 0.0, width * 0.5, '[Name]', rnd.choice([8.0, 12.0]), grow=True, border=rnd.random() < 0.3),
                       text_element(width * 0.75, 0.0, width * 0.25, '[Amount:1]', 8.0, align='Right')]
    if rnd.random() < 0.5:
        detail_elements.append(text_element(0.0, 10.0, width, '#[ROW] qty [Qty]', 8.0, h=10.0))
    band('Detail', rnd.choice([10.0, 12.0, 15.0]), detail_elements)
    for l in range(ngroups - 1, -1, -1):
        band('GroupFooter', rnd.choice([12.0, 16.0]), [text_element(0.0, 0.0, width, 'sum [SUM(Amount)] avg [AVG(Amount):1] min [MIN(Amount)] max [MAX(Qty):0] [[end]]', 8.0, grow=True)], l)
    if rnd.random() < 0.7:
        band('ReportFooter', rnd.choice([12.0, 20.0]), [text_element(0.0, 0.0, width, 'Grand total [SUM(Amount)] over [COUNT(Name)] rows', 12.0, bold=True)])
    if rnd.random() < 0.8:
        band('PageFooter', rnd.choice([10.0, 14.0]), [line_element(0.0), text_element(0.0, 2.0, width, 'page [PAGE]', 8.0, align='Right')])
    rnd.shuffle(bands) if False else None
    # sorted data needs the sort flag unless the rows are put in order here
    sort = True
    if ngroups and rnd.random() < 0.4:
        cols = [columns.index(x['field']) for x in groups]
        rows.sort(key=lambda r: tuple(r[c][0].encode() for c in cols))
        sort = False
    return Report(page, margins, bands, groups, columns, rows, sort)


def build_cases():
    cases = []
    for index in range(80):
        rep = make_case(index)
        pages = Run(rep).layout()
        text = dump(pages)
        cases.append((rep, len(pages), [len(items) for _, items in pages], fnv(text), text))
    return cases


def e_float(v):
    return ('%r' % float(v)) if float(v) != int(v) else '%d.0' % int(v)


def element_src(el):
    return ('rp.Element { kind: .%s, x: %s, y: %s, width: %s, height: %s, text: %s, size: %s, bold: %s, align: .%s, border: %s, grow: %s }' % (
        el['kind'], e_float(el['x']), e_float(el['y']), e_float(el['width']), e_float(el['height']), quote(el['text']), e_float(el['size']),
        'true' if el['bold'] else 'false', el['align'], 'true' if el['border'] else 'false', 'true' if el['grow'] else 'false'))


def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def case_fn(k, case):
    rep, count, per_page, h, _ = case
    lines = ['fn case_%d(a: *mem.Arena) -> i32 {' % k]
    for b, band in enumerate(rep.bands):
        els = ', '.join(element_src(e) for e in band['elements'])
        lines.append('    let els_%d = [%d]rp.Element{ %s }' % (b, len(band['elements']), els))
    bands = ', '.join('rp.Band { kind: .%s, height: %s, elements: els_%d[0..], level: %dusize, page_break_before: %s }' % (
        b['kind'], e_float(b['height']), i, b['level'], 'true' if b['page_break_before'] else 'false') for i, b in enumerate(rep.bands))
    lines.append('    let bands = [%d]rp.Band{ %s }' % (len(rep.bands), bands))
    if rep.groups:
        groups = ', '.join('rp.Group { field: %s, keep_together: %s, repeat_header: %s }' % (quote(g['field']), 'true' if g['keep_together'] else 'false', 'true' if g['repeat_header'] else 'false') for g in rep.groups)
        lines.append('    let groups = [%d]rp.Group{ %s }' % (len(rep.groups), groups))
    else:
        lines.append('    let groups: [0]rp.Group = zero')
    cols = ', '.join(quote(c) for c in rep.columns)
    lines.append('    let columns = [%d]str{ %s }' % (len(rep.columns), cols))
    cells = ', '.join('rp.Cell { text: %s, number: %s, numeric: %s }' % (quote(c[0]), e_float(c[1]), 'true' if c[2] else 'false') for row in rep.rows for c in row)
    if rep.rows:
        lines.append('    let cells = [%d]rp.Cell{ %s }' % (len(rep.rows) * len(rep.columns), cells))
    else:
        lines.append('    let cells: [0]rp.Cell = zero')
    lines.append('    let source = rp.Source { columns: columns[0..], cells: cells[0..], rows: %dusize }' % len(rep.rows))
    lines.append('    let report = rp.Report { page_width: %s, page_height: %s, margin_left: %s, margin_top: %s, margin_right: %s, margin_bottom: %s, bands: bands[0..], groups: groups[0..], source: source, sort: %s }' % (
        e_float(rep.pw), e_float(rep.ph), e_float(rep.ml), e_float(rep.mt), e_float(rep.mr), e_float(rep.mb), 'true' if rep.sort else 'false'))
    counts = ', '.join('%dusize' % c for c in per_page)
    lines.append('    let counts = [%d]usize{ %s }' % (len(per_page), counts))
    lines.append('    ret check(a, &report, %dusize, counts[0..], %du64)' % (count, h))
    lines.append('}')
    return '\n'.join(lines)


def main():
    cases = build_cases()
    template = (root / 'scripts' / 'report_fixture_template.e').read_text(encoding='utf-8')
    fns = '\n\n'.join(case_fn(k, c) for k, c in enumerate(cases))
    calls = '\n'.join('    let code_%d = case_%d(a)\n    if code_%d != 0i32 { ret fail(%di32 + code_%d) }' % (k, k, k, (k + 1) * 100, k) for k in range(len(cases)))
    text = template.replace('@@CASES@@', fns).replace('@@CALLS@@', calls).replace('@@COUNT@@', str(len(cases)))
    out = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'ui_report' / 'src'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'main.e').write_text(text, encoding='utf-8', newline='\n')
    pages = sum(c[1] for c in cases)
    print('wrote ui_report: %d reports, %d pages, max %d pages' % (len(cases), pages, max(c[1] for c in cases)))


main()
