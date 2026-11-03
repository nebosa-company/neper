"""Bakes the skins of the Windows dialog bodies into lib/e/ui/windlg88.e from ref/windows-1to1/states (round 88).
Per body: the chrome tile (every pixel of the window below the caption except text, pictures and buttons; mapped by the dark look when drawn),
the picture tiles (v3 artwork, raw colours) and the label list (text, position, ink, weight), all read from the 1:1 capture.
Edit this script, scripts/x88_specs.py and scripts/x88_adj.json (the per-label corrections measured from our renders), not the generated file.
Run from the repository root: python -I scripts/gen_x88.py"""
import json
import os
import sys

import numpy as np
from PIL import Image

CAP = 'docs/ui/looks/ref/windows-1to1/states/'
ADJ = 'scripts/x88_adj.json'
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from x88_specs import SPECS  # noqa: E402


def mode_color(px):
    vals, counts = np.unique(px.reshape(-1, 3), axis=0, return_counts=True)
    return tuple(int(v) for v in vals[counts.argmax()])


def ink_box(c, box, thresh=70):
    x0, y0, x1, y1 = box
    reg = c[y0:y1, x0:x1].astype(int)
    bg = np.array(mode_color(reg))
    d = np.abs(reg - bg).max(axis=2)
    ys, xs = np.where(d > thresh)
    if len(ys) == 0:
        return None
    # the ink colour: the mean of the darkest pixels (ClearType fringes are no ink); near black is black
    px = reg[ys, xs]
    luma = px[:, 0] * 0.299 + px[:, 1] * 0.587 + px[:, 2] * 0.114
    order = np.argsort(luma)[:max(3, len(ys) // 25)]
    ink = tuple(int(v) for v in px[order].mean(axis=0))
    if max(ink) < 0x58 and min(bg) > 0x90:
        ink = (0, 0, 0)
    return (x0 + int(xs.min()), y0 + int(ys.min()), x0 + int(xs.max()), y0 + int(ys.max()), ink, tuple(int(v) for v in bg))


def rle(rows):
    out = []
    for row in rows:
        i = 0
        while i < len(row):
            j = i
            while j < len(row) and row[j] == row[i] and j - i < 256:
                j += 1
            out.append('%s%02X' % (row[i], j - i - 1))
            i = j
    return ''.join(out)


def hexpx(c):
    return '%02X%02X%02X' % tuple(int(v) for v in c)


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def col_class(px):
    r, g, b = [int(v) for v in px]
    if r < 100 and g < 100 and b < 100:
        return 'k'
    if g > r + 30 and g > b + 30:
        return 'g'
    if r > g + 40 and r > b + 40:
        return 'm'
    return 'o'


def expand_run(capc, t):
    """('RUN', (x0, y0, x1, y1), [(text, class, opts), ...]): one line of differently styled runs; the runs are the stretches of ink columns of one colour class
    (k black, g green, m maroon), in order. Returns one label entry per run with a box of the run's own columns."""
    box, segs = t[1], t[2]
    x0, y0, x1, y1 = box
    reg = capc[y0:y1, x0 - 8:x1 - 8].astype(int)
    bg = np.array(mode_color(reg))
    d = np.abs(reg - bg).max(axis=2)
    cls = []
    for x in range(reg.shape[1]):
        col = np.where(d[:, x] > 150)[0]
        if len(col) == 0:
            cls.append(None)
            continue
        j = col[np.argmin(reg[col, x].sum(axis=1))]
        cls.append(col_class(reg[j, x]))
    runs = []
    cur = None
    for x, c in enumerate(cls):
        if c is None:
            continue
        if cur is None or cur[2] != c:
            if cur is not None:
                runs.append(cur)
            cur = [x, x, c]
        else:
            cur[1] = x
    if cur is not None:
        runs.append(cur)
    if len(runs) != len(segs):
        print('RUN: %d runs for %d segments' % (len(runs), len(segs)), [r[2] for r in runs], [s_[0] for s_ in segs])
        return []
    out = []
    for (a, b, c), seg in zip(runs, segs):
        opt = dict(seg[2]) if len(seg) > 2 else {}
        out.append((seg[0], (x0 + a - 1, y0, x0 + b + 2, y1), opt))
    return out


def build(adj):
    ids = list(SPECS.keys())
    body = {}
    for n, name in enumerate(ids):
        s = SPECS[name]
        im = np.array(Image.open(CAP + s['cap'] + '@1x.png').convert('RGB'))
        w, h = s['w'], s['h']
        c = im[0:h, 8:8 + w].copy()
        capc = c.copy()
        for (x0, y0, x1, y1, col) in s.get('erase', []):
            c[y0:y1, x0 - 8:x1 - 8] = col
        labels = []
        texts = []
        for t in s['texts']:
            if t[0] == 'RUN':
                texts += expand_run(capc, t)
            else:
                texts.append(t)
        for k, t in enumerate(texts):
            text, box = t[0], t[1]
            opt = t[2] if len(t) > 2 else {}
            ib = ink_box(capc, (box[0] - 8, box[1], box[2] - 8, box[3]), opt.get('thresh', 70))
            if ib is None:
                print('no ink for', name, text)
                continue
            x0, y0, x1, y1, ink, bg = ib
            c[box[1]:box[3], box[0] - 8:box[2] - 8] = bg
            ax, ay = adj.get('%s/%d' % (name, len(labels)), [0, 0])
            col = opt.get('ink', ink)
            labels.append((text, x0 + ax + opt.get('ox', 0), y0 + ay + opt.get('oy', 0), col, opt.get('weight', 400), opt.get('face', 8), 1 if opt.get('underline') else 0, opt.get('size', 11)))
        pics = []
        for pic in s.get('pics', []):
            (px0, py0, px1, py1), pkey = pic[:4], (pic[4] if len(pic) > 4 else s.get('key'))
            reg = capc[py0:py1, px0 - 8:px1 - 8].astype(int)
            lv = s.get('levels', 0)
            if lv:   # artwork too rich for the scene's 4 MB of commands (one rectangle per run of equal pixels): pixel pairs, n luminance levels, each its mean colour
                bw = s.get('block', 1)
                pairs = reg.reshape(reg.shape[0], reg.shape[1] // bw, bw, 3).mean(axis=2)
                lum = (pairs * [0.299, 0.587, 0.114]).sum(axis=2)
                idx = np.round(lum / 255 * (lv - 1)).astype(int)
                pal = [pairs[idx == k].mean(axis=0).round().astype(int) if (idx == k).any() else np.zeros(3, int) for k in range(lv)]
                reg = np.repeat(np.array(pal)[idx], bw, axis=1)
            if pkey:
                kc = tuple(pkey)
                grid = [[('ZZZZZZ' if tuple(int(v) for v in reg[y, x]) == kc else hexpx(reg[y, x])) for x in range(reg.shape[1])] for y in range(reg.shape[0])]
            else:
                grid = [[hexpx(reg[y, x]) for x in range(reg.shape[1])] for y in range(reg.shape[0])]
            pics.append((px0 - 8, py0, px1 - px0, py1 - py0, rle(grid)))
        rows = []
        for y in range(31, h):
            row = [hexpx(c[y, x]) for x in range(w)]
            for pic in s.get('pics', []):
                px0, py0, px1, py1 = pic[:4]
                if py0 <= y < py1:
                    for x in range(px0 - 8, px1 - 8):
                        row[x] = 'ZZZZZZ'
            rows.append(row)
        body[name] = (n, w, h - 31, rle(rows), pics, labels)

    src = '// Generated by scripts/gen_x88.py from ref/windows-1to1/states; edit the script and scripts/x88_specs.py.\n'
    src += '// A skin is run length coded: eight hex digits a run, RRGGBB and the run length less one; ZZZZZZ is transparent.\n\n'
    src += 'fn count() -> usize { ret %dusize }\n' % len(ids)

    def table(fname, vals, kind='usize'):
        o = 'fn %s(id: usize) -> %s {\n' % (fname, kind)
        for i, v in enumerate(vals):
            o += '    if id == %dusize { ret %s }\n' % (i, ('%dusize' % v) if kind == 'usize' else repr(float(v)))
        return o + ('    ret 0usize\n}\n' if kind == 'usize' else '    ret 0.0\n}\n')

    src += table('skin_w', [body[k][1] for k in ids])
    src += table('skin_h', [body[k][2] for k in ids])
    src += table('pic_count', [len(body[k][4]) for k in ids])
    src += table('label_count', [len(body[k][5]) for k in ids])
    src += 'fn skin(id: usize) -> str {\n'
    for name in ids:
        src += '    if id == %dusize { ret "%s" }\n' % (body[name][0], body[name][3])
    src += '    ret ""\n}\n'
    for fname, idx in (('pic_x', 0), ('pic_y', 1), ('pic_w', 2), ('pic_h', 3)):
        src += 'fn %s(id: usize, k: usize) -> f32 {\n' % fname
        for name in ids:
            for k, p in enumerate(body[name][4]):
                src += '    if id == %dusize && k == %dusize { ret %s }\n' % (body[name][0], k, repr(float(p[idx])))
        src += '    ret 0.0\n}\n'
    src += 'fn pic(id: usize, k: usize) -> str {\n'
    for name in ids:
        for k, p in enumerate(body[name][4]):
            src += '    if id == %dusize && k == %dusize { ret "%s" }\n' % (body[name][0], k, p[4])
    src += '    ret ""\n}\n'
    src += 'fn label_text(id: usize, k: usize) -> str {\n'
    for name in ids:
        for k, l in enumerate(body[name][5]):
            src += '    if id == %dusize && k == %dusize { ret "%s" }\n' % (body[name][0], k, esc(l[0]))
    src += '    ret ""\n}\n'
    for fname, idx in (('label_x', 1), ('label_y', 2)):
        src += 'fn %s(id: usize, k: usize) -> f32 {\n' % fname
        for name in ids:
            for k, l in enumerate(body[name][5]):
                src += '    if id == %dusize && k == %dusize { ret %s }\n' % (body[name][0], k, repr(float(l[idx])))
        src += '    ret 0.0\n}\n'
    src += 'fn label_ink(id: usize, k: usize) -> u32 {\n'
    for name in ids:
        for k, l in enumerate(body[name][5]):
            c = l[3]
            src += '    if id == %dusize && k == %dusize { ret 0x%02X%02X%02Xu32 }\n' % (body[name][0], k, c[0], c[1], c[2])
    src += '    ret 0u32\n}\n'
    for fname, idx in (('label_weight', 4), ('label_face', 5), ('label_underline', 6), ('label_size', 7)):
        src += 'fn %s(id: usize, k: usize) -> u32 {\n' % fname
        for name in ids:
            for k, l in enumerate(body[name][5]):
                src += '    if id == %dusize && k == %dusize { ret %du32 }\n' % (body[name][0], k, l[idx])
        src += '    ret 0u32\n}\n'
    open('lib/e/ui/windlg88.e', 'w', encoding='utf-8').write(src)
    print('wrote lib/e/ui/windlg88.e', len(src), 'bytes;', ', '.join('%s %d labels' % (k, len(body[k][5])) for k in ids))
    json.dump({k: [(t[1], t[2]) for t in body[k][5]] for k in ids}, open('D:/Temp/lanes/tools/x88_labels.json', 'w'))


if __name__ == '__main__':
    adj = json.load(open(ADJ)) if os.path.exists(ADJ) else {}
    build(adj)
