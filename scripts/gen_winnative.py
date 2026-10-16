# Generates lib/e/ui/winnative.e: pixel tables read from the native Windows 11 captures in
# docs/ui/looks/ref/windows-native (round 10). Run: python -I scripts/gen_winnative.py  (from the repository root).
# The Windows dark look paints its button ring, marks and edit chrome from these tables; edit this script, not the output.
import sys, os
from PIL import Image, ImageChops
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace(chr(92), '/')
REF = ROOT + '/docs/ui/looks/ref/windows-native/'


def load(theme, name):
    return Image.open(REF + f'{theme}/{name}@1x.png').convert('RGB')


def trim(im):
    bg = im.getpixel((0, 0))
    d = ImageChops.difference(im, Image.new('RGB', im.size, bg)).convert('L').point(lambda v: 255 if v > 6 else 0)
    b = d.getbbox()
    return im.crop(b), b


def u(p):
    return '0x%02X%02X%02X%02Xu32' % (255, p[0], p[1], p[2])


def fn_table(name, ty, values):
    return 'fn %s() -> %s { ret %s{ %s } }' % (name, ty, ty, ', '.join(values))


sections = []


# ---- button ring: kinds 0 rest, 1 default, 2 disabled, 3 pressed (dark) ----
def ring_section():
    kinds = [('button-rest', 0), ('button-default', 1), ('button-disabled', 2), ('button-pressed', 3)]
    lines = ['// The dark button ring (native DarkMode button, 108 x 30 visible box): per kind the top-left 6 x 6 corner then the bottom-left one,',
             '// the right corners mirror them. Colours: ring line, bottom shadow row, face.']
    for nm, k in kinds:
        t, _ = trim(load('dark', nm))
        w, h = t.size
        tl = [t.getpixel((i, j)) for j in range(6) for i in range(6)]
        bl = [t.getpixel((i, h - 6 + j)) for j in range(6) for i in range(6)]
        line = t.getpixel((w // 2, 0))
        shadow = t.getpixel((w // 2, h - 1))
        face = t.getpixel((w // 2, 3))
        lines.append(fn_table('nring_corners_%d' % k, '[72]u32', [u(p) for p in tl + bl]))
        lines.append('fn nring_line_%d() -> u32 { ret %s }' % (k, u(line)))
        lines.append('fn nring_shadow_%d() -> u32 { ret %s }' % (k, u(shadow)))
        lines.append('fn nring_face_%d() -> u32 { ret %s }' % (k, u(face)))
    return '\n'.join(lines)


sections.append(ring_section())


# ---- check box and radio marks: 13 x 13 tiles, ARGB with the edge's coverage as alpha ----
def mark_tile(theme, name):
    im = load(theme, name)
    bg = im.getpixel((0, 0))
    full, bb = trim(im)
    # the box is the leftmost 16 columns of the capture's ink (the caption starts further right)
    box = im.crop((bb[0], bb[1], bb[0] + 16, bb[3]))
    inner, ib = trim_with(box, bg)
    x0 = bb[0] + ib[0]
    y0 = bb[1] + ib[1]
    px = [[im.getpixel((x0 + i, y0 + j)) for i in range(13)] for j in range(13)]
    edge = px[0][6]
    # pixels equal to the background and connected to the tile's border are outside the shape; the dot of a disabled radio may
    # share the background's value without being outside
    reach = set()
    stack = [(i, j) for i in range(13) for j in range(13) if (i in (0, 12) or j in (0, 12)) and px[j][i] == bg]
    while stack:
        i, j = stack.pop()
        if (i, j) in reach:
            continue
        reach.add((i, j))
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x, y = i + di, j + dj
            if 0 <= x < 13 and 0 <= y < 13 and px[y][x] == bg and (x, y) not in reach:
                stack.append((x, y))

    def outside(i, j):
        return i < 0 or j < 0 or i > 12 or j > 12 or (i, j) in reach
    out = []
    for j in range(13):
        for i in range(13):
            p = px[j][i]
            if (i, j) in reach:
                out.append(0)
                continue
            near_out = any(outside(i + di, j + dj) for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if near_out and edge != bg:
                num = sum((p[c] - bg[c]) * (edge[c] - bg[c]) for c in range(3))
                den = sum((edge[c] - bg[c]) ** 2 for c in range(3))
                a = max(0.0, min(1.0, num / den))
                out.append((int(a * 255 + 0.5) << 24) | (edge[0] << 16) | (edge[1] << 8) | edge[2])
            else:
                out.append(0xFF000000 | (p[0] << 16) | (p[1] << 8) | p[2])
    return out, (x0, y0)


def trim_with(im, bg):
    d = ImageChops.difference(im, Image.new('RGB', im.size, bg)).convert('L').point(lambda v: 255 if v > 6 else 0)
    b = d.getbbox()
    return im.crop(b), b


def marks_section():
    lines = ['// Check box and radio marks of the native theme, 13 x 13, ARGB (the edge pixels carry their coverage). Ids: check box off 0, on 1, mixed 2,',
             '// radio off 3, on 4; each in rest (0), pressed (1) and disabled (2): id * 3 + state. Theme 0 light, 1 dark.']
    for ti, theme in enumerate(['light', 'dark']):
        for ci, (ctl, st) in enumerate([('checkbox-unchecked', 0), ('checkbox-checked', 1), ('checkbox-indeterminate', 2), ('radio-unchecked', 3), ('radio-checked', 4)]):
            for si, sname in enumerate(['rest', 'pressed', 'disabled']):
                try:
                    tile, at = mark_tile(theme, '%s-%s' % (ctl, sname))
                except TypeError:
                    # the native light radio-checked-pressed capture is blank; v3's own pressed radio is the reference there
                    tile, at = mark_tile(theme, '%s-rest' % ctl)
                vals = ['0x%08Xu32' % v for v in tile]
                lines.append('fn nmark_%d_%d() -> [169]u32 { ret [169]u32{ %s } }' % (ti, ci * 3 + si, ', '.join(vals)))
    lines.append('fn nmark(theme: u32, id: u32) -> [169]u32 {')
    for ti in range(2):
        for k in range(15):
            lines.append('    if theme == %du32 && id == %du32 { ret nmark_%d_%d() }' % (ti, k, ti, k))
    lines.append('    ret nmark_0_0()')
    lines.append('}')
    return chr(10).join(lines)


sections.append(marks_section())


# ---- the spin edit (native edit + up-down, 24 rows): left 3 columns, one middle column, right 18 columns per row ----
SPIN_STATES = ['rest', 'focus', 'hover-up', 'hover-down', 'pressed-up', 'pressed-down', 'disabled']


def spin_section():
    lines = ['// The native dark spin edit, 24 rows: per state 3 left columns, the middle column (replicated) and the 18 right columns (the up-down) of every row.',
             '// States: 0 rest, 1 focus, 2 hover up, 3 hover down, 4 pressed up, 5 pressed down, 6 disabled.']
    for i, st in enumerate(SPIN_STATES):
        t, _ = trim(load('dark', 'spin-' + st))
        w, h = t.size
        assert h == 24, (st, h)
        vals = []
        for j in range(h):
            for x in list(range(0, 3)) + [30] + list(range(w - 18, w)):
                p = t.getpixel((x, j))
                vals.append(u(p))
        lines.append(fn_table('nspin_%d' % i, '[528]u32', vals))
    lines.append('fn nspin(state: u32) -> [528]u32 {')
    for i in range(len(SPIN_STATES)):
        lines.append('    if state == %du32 { ret nspin_%d() }' % (i, i))
    lines.append('    ret nspin_0()')
    lines.append('}')
    return chr(10).join(lines)


sections.append(spin_section())


# ---- the combo box chevron: 10 x 6 at (w - 14, 9) of the native 150 x 23 combo, baked over the button face ----
def chevron_section():
    lines = ['// The native dark combo chevron, 10 x 6 (opaque, over the face it stands on): 0 combo edit rest (#383838), 1 list rest (#333333),',
             '// 2 disabled, 3 open or pressed (#666666). It stands at (w - 14, 9) in a 23 high combo.']
    for i, nm in enumerate(['combo-edit-rest', 'combo-list-rest', 'combo-list-disabled', 'combo-list-open']):
        t, _ = trim(load('dark', nm))
        w, h = t.size
        vals = [u(t.getpixel((w - 14 + x, 9 + y))) for y in range(6) for x in range(10)]
        lines.append(fn_table('nchev_%d' % i, '[60]u32', vals))
    lines.append('fn nchev(id: u32) -> [60]u32 {')
    for i in range(4):
        lines.append('    if id == %du32 { ret nchev_%d() }' % (i, i))
    lines.append('    ret nchev_0()')
    lines.append('}')
    return chr(10).join(lines)


sections.append(chevron_section())

header = '''// GENERATED by scripts/gen_winnative.py from docs/ui/looks/ref/windows-native: pixel tables of the native Windows 11
// controls (round 10). A value is 0xAARRGGBB. Edit the script, not this file.

'''
open(ROOT + '/lib/e/ui/winnative.e', 'w', encoding='utf-8', newline='\n').write(header + '\n\n'.join(sections) + '\n')
print('written')
