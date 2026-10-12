"""Reference numbers for the MATH-table, cramped-style, assembly, align, MathML and drawing
checks of the text_math fixture (L098, D3101).

A small model of TeX's layout rules with OpenType MATH constants, written separately from
the library: it reads the same font file with fontTools (hmtx, cmap, glyf, and the MATH
table's constants, italic corrections and variants), lays each expression out directly and
prints Neper check code between the markers of tests/selfhost/fixtures/link/text_math/src/main.e.
The pixel references render the same items with Pillow at 8x and box-reduce them.

    python scripts/gen_math_font.py
    python scripts/gen_math_render_test.py
"""
import io
import os
import sys
import unicodedata

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MATH_FONT = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "text_math", "assets", "mathfont.ttf")
PLAIN_FONT = os.path.join(ROOT, "docs", "video", "neper-capabilities", "fonts", "Montserrat-ExtraBold.ttf")
MAIN = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "text_math", "src", "main.e")

CLS_ORD, CLS_OP, CLS_BIN, CLS_REL, CLS_OPEN, CLS_CLOSE, CLS_PUNCT, CLS_INNER, CLS_SPACE = range(9)
SPACING = "01bc000a110c000abb00b00bcc00c00c0000000001bc000aaa0aaaaaa1bca0aa"


class Face:
    def __init__(self, path):
        self.f = TTFont(path)
        self.cmap = self.f.getBestCmap()
        self.upem = self.f["head"].unitsPerEm
        self.hmtx = self.f["hmtx"]
        self.glyf = self.f["glyf"]
        x = self.glyf[self.cmap[ord("x")]]
        xh = x.yMax / self.upem
        k = dict(
            axis=0.25, rule=0.04, script=0.7, scriptscript=0.5,
            num_display=0.677, num_text=0.394, den_display=0.686, den_text=0.345,
            num_gap=0.04, num_gap_display=0.12, den_gap=0.04, den_gap_display=0.12,
            sup_display=0.413, sup_text=0.363, sup_cramped=0.289, sub_only=0.15, sub_both=0.247,
            sub_top_max=0.8 * xh, sup_bottom_min=0.25 * xh, sup_max_with_sub=0.8 * xh, sub_sup_gap=0.16,
            sup_drop=0.386, sub_drop=0.05, script_space=0.05, upper_gap=0.12, lower_gap=0.12,
            rad_rule=0.04, rad_gap=0.05, rad_gap_display=0.04 + 0.25 * xh, rad_extra=0.0,
            rad_before=0.0, rad_after=-5.0 / 18.0, rad_raise=0.6, delim_min=1.2, op_min=0.0,
            # TeX rules 9 and 12: overline 3 rule thicknesses up, one of rule and one extra; the
            # accent is designed for the x-height; stretch gaps default to the limit gaps.
            accent_base=xh, over_gap=0.12, over_rule=0.04, over_extra=0.04,
            under_gap=0.12, under_rule=0.04, under_extra=0.04, stretch_above=0.12, stretch_below=0.12,
        )
        self.math = "MATH" in self.f
        self.ital = {}
        self.top_attach = {}
        self.kern = {}
        self.hcons = {}
        self.cons = {}
        self.assembly = {}
        self.overlap = 0
        if self.math:
            t = self.f["MATH"].table
            c = t.MathConstants
            v = lambda n: getattr(c, n).Value / self.upem
            k.update(
                script=c.ScriptPercentScaleDown / 100.0, scriptscript=c.ScriptScriptPercentScaleDown / 100.0,
                delim_min=c.DelimitedSubFormulaMinHeight / self.upem, op_min=c.DisplayOperatorMinHeight / self.upem,
                axis=v("AxisHeight"), sub_only=v("SubscriptShiftDown"), sub_both=v("SubscriptShiftDown"),
                sub_top_max=v("SubscriptTopMax"), sub_drop=v("SubscriptBaselineDropMin"),
                sup_display=v("SuperscriptShiftUp"), sup_text=v("SuperscriptShiftUp"),
                sup_cramped=v("SuperscriptShiftUpCramped"), sup_bottom_min=v("SuperscriptBottomMin"),
                sup_drop=v("SuperscriptBaselineDropMax"), sub_sup_gap=v("SubSuperscriptGapMin"),
                sup_max_with_sub=v("SuperscriptBottomMaxWithSubscript"), script_space=v("SpaceAfterScript"),
                upper_gap=v("UpperLimitGapMin"), lower_gap=v("LowerLimitGapMin"),
                num_text=v("FractionNumeratorShiftUp"), num_display=v("FractionNumeratorDisplayStyleShiftUp"),
                den_text=v("FractionDenominatorShiftDown"), den_display=v("FractionDenominatorDisplayStyleShiftDown"),
                num_gap=v("FractionNumeratorGapMin"), num_gap_display=v("FractionNumDisplayStyleGapMin"),
                rule=v("FractionRuleThickness"), den_gap=v("FractionDenominatorGapMin"),
                den_gap_display=v("FractionDenomDisplayStyleGapMin"),
                rad_gap=v("RadicalVerticalGap"), rad_gap_display=v("RadicalDisplayStyleVerticalGap"),
                rad_rule=v("RadicalRuleThickness"), rad_extra=v("RadicalExtraAscender"),
                rad_before=v("RadicalKernBeforeDegree"), rad_after=v("RadicalKernAfterDegree"),
                rad_raise=c.RadicalDegreeBottomRaisePercent / 100.0,
                accent_base=v("AccentBaseHeight"),
                over_gap=v("OverbarVerticalGap"), over_rule=v("OverbarRuleThickness"), over_extra=v("OverbarExtraAscender"),
                under_gap=v("UnderbarVerticalGap"), under_rule=v("UnderbarRuleThickness"),
                under_extra=v("UnderbarExtraDescender"),
                stretch_above=v("StretchStackGapAboveMin"), stretch_below=v("StretchStackGapBelowMin"),
            )
            ic = t.MathGlyphInfo.MathItalicsCorrectionInfo
            for name, rec in zip(ic.Coverage.glyphs, ic.ItalicsCorrection):
                self.ital[name] = rec.Value / self.upem
            ta = t.MathGlyphInfo.MathTopAccentAttachment
            if ta is not None:
                for name, rec in zip(ta.TopAccentCoverage.glyphs, ta.TopAccentAttachment):
                    self.top_attach[name] = rec.Value / self.upem
            ki = t.MathGlyphInfo.MathKernInfo
            if ki is not None:
                for name, rec in zip(ki.MathKernCoverage.glyphs, ki.MathKernInfoRecords):
                    corners = {}
                    for corner, field in (("tr", "TopRightMathKern"), ("tl", "TopLeftMathKern"),
                                          ("br", "BottomRightMathKern"), ("bl", "BottomLeftMathKern")):
                        mk = getattr(rec, field)
                        if mk is not None:
                            corners[corner] = ([h.Value for h in mk.CorrectionHeight], [kv.Value for kv in mk.KernValue])
                    self.kern[name] = corners
            mv = t.MathVariants
            self.overlap = mv.MinConnectorOverlap / self.upem
            for name, con in zip(mv.VertGlyphCoverage.glyphs, mv.VertGlyphConstruction):
                self.cons[name] = con
            if mv.HorizGlyphCoverage is not None:
                for name, con in zip(mv.HorizGlyphCoverage.glyphs, mv.HorizGlyphConstruction):
                    self.hcons[name] = con
        self.k = type("K", (), k)

    def name(self, scalar):
        return self.cmap.get(scalar)

    def gid(self, name):
        return self.f.getGlyphID(name)

    def adv(self, name):
        return self.hmtx[name][0] / self.upem

    def ext(self, name):
        g = self.glyf[name]
        if g.numberOfContours == 0:
            return 0.0, 0.0
        return g.yMin / self.upem, g.yMax / self.upem


class Atom:
    def __init__(self, cls=CLS_ORD):
        self.cls = cls
        self.items = []
        self.w = self.h = self.d = 0.0
        self.simple = False
        self.limits = False
        self.stretch = False

    def shift(self, dx, dy):
        for it in self.items:
            it["x"] += dx
            it["y"] += dy


# D3702: alphabets by Unicode name (no code point arithmetic), accents, bars, braces, kerns.
ALPHABET_NAMES = {"bold": "BOLD", "bold_italic": "BOLD ITALIC", "script": "SCRIPT", "fraktur": "FRAKTUR",
                  "double": "DOUBLE-STRUCK", "sans": "SANS-SERIF", "mono": "MONOSPACE"}
LETTERLIKE = {"SCRIPT": "SCRIPT", "FRAKTUR": "BLACK-LETTER", "DOUBLE-STRUCK": "DOUBLE-STRUCK"}
DIGITS = "ZERO ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE".split()


def alphabet_scalar(face, scalar, alphabet):
    """`scalar` in the named alphabet when the font has a glyph for it, else itself."""
    if alphabet is None:
        return italic_scalar(face, scalar)
    base = ALPHABET_NAMES[alphabet]
    ch = chr(scalar)
    names = []
    if ch.isascii() and ch.isalpha():
        kind = "CAPITAL" if ch.isupper() else "SMALL"
        names.append("MATHEMATICAL %s %s %s" % (base, kind, ch.upper()))
        if base in LETTERLIKE:
            names.append("%s %s %s" % (LETTERLIKE[base], kind, ch.upper()))
    elif ch.isdigit() and ch.isascii():
        names.append("MATHEMATICAL %s DIGIT %s" % (base, DIGITS[int(ch)]))
    elif unicodedata.name(ch, "").startswith("GREEK SMALL LETTER"):
        names.append("MATHEMATICAL %s SMALL %s" % (base, unicodedata.name(ch)[len("GREEK SMALL LETTER "):]))
    for name in names:
        try:
            want = ord(unicodedata.lookup(name))
        except KeyError:
            continue
        if face.name(want):
            return want
    return scalar


def kern_value(face, name, corner, height, size):
    """MathKernInfo's step function: the first correction height above `height`, else the last."""
    spec = face.kern.get(name, {}).get(corner)
    if spec is None:
        return 0.0
    heights, kerns = spec
    units = height / size * face.upem
    i = 0
    while i < len(heights) and units >= heights[i]:
        i += 1
    return kerns[i] / face.upem * size


def italic_scalar(face, scalar):
    want = 0
    if 97 <= scalar <= 122:
        want = 119886 + scalar - 97
        if scalar == 104:
            want = 8462
    elif 65 <= scalar <= 90:
        want = 119860 + scalar - 65
    elif 945 <= scalar <= 969:
        want = 120572 + scalar - 945
    if want and face.name(want):
        return want
    return scalar


def glyph(face, scalar, size, cls, italic=True, alphabet=None):
    shown = alphabet_scalar(face, scalar, alphabet) if italic else scalar
    name = face.name(shown)
    a = Atom(cls)
    a.simple = True
    adv = face.adv(name) * size
    low, high = face.ext(name)
    a.items.append(dict(kind="glyph", x=0.0, y=0.0, w=adv, h=0.0, size=size, glyph=face.gid(name), scalar=shown, name=name))
    a.w = adv
    a.h = max(high * size, 0.0)
    a.d = max(-low * size, 0.0)
    return a


def scale(face, style):
    b = style & 3
    return face.k.scriptscript if b >= 3 else (face.k.script if b == 2 else 1.0)


def script_style(style):
    return (2 if (style & 3) < 2 else 3) | (style & 4)


def fraction_style(style):
    return (3 if (style & 3) >= 3 else (style & 3) + 1) | (style & 4)


def spacing(left, right, script):
    code = SPACING[left * 8 + right]
    if code == "0":
        return 0
    if code in "123":
        return {"1": 3, "2": 4, "3": 5}[code]
    if script:
        return 0
    return {"a": 3, "b": 4, "c": 5}.get(code, 0)


def row(face, S, atoms, style):
    out = Atom()
    atoms = list(atoms)
    for i, a in enumerate(atoms):
        if a.cls == CLS_BIN:
            before = CLS_OPEN
            for j in range(i - 1, -1, -1):
                if atoms[j].cls != CLS_SPACE:
                    before = atoms[j].cls
                    break
            after = CLS_CLOSE
            j = i + 1
            while j < len(atoms):
                if atoms[j].cls != CLS_SPACE:
                    after = atoms[j].cls
                    break
                j += 1
            if i == 0 or before in (CLS_BIN, CLS_OP, CLS_REL, CLS_OPEN, CLS_PUNCT) or after in (CLS_REL, CLS_CLOSE, CLS_PUNCT) or j >= len(atoms):
                a.cls = CLS_ORD
    em18 = S * scale(face, style) / 18.0
    x = 0.0
    prev = CLS_SPACE
    for a in atoms:
        if a.cls != CLS_SPACE:
            if prev != CLS_SPACE:
                x += spacing(prev, a.cls, (style & 3) >= 2) * em18
            prev = a.cls
        else:
            prev = CLS_SPACE
        a.shift(x, 0.0)
        out.items += a.items
        x += a.w
        out.h = max(out.h, a.h)
        out.d = max(out.d, a.d)
    out.w = x
    return out


def scripts(face, S, nucleus, sup, sub, style, display, sub_first=False):
    k = face.k
    s = S * scale(face, style)
    sstyle = script_style(style)
    ss = S * scale(face, sstyle)
    disp = display and (style & 3) == 0
    out = Atom()
    if nucleus.limits and (disp or nucleus.stretch):
        width = max(nucleus.w, sup.w if sup else 0, sub.w if sub else 0)
        nucleus.shift((width - nucleus.w) / 2, 0)
        h, d = nucleus.h, nucleus.d
        items = list(nucleus.items)
        sup_items = sub_items = []
        if sup:
            up = nucleus.h + k.upper_gap * s + sup.d
            sup.shift((width - sup.w) / 2, -up)
            h = up + sup.h
            sup_items = sup.items
        if sub:
            down = nucleus.d + k.lower_gap * s + sub.h
            sub.shift((width - sub.w) / 2, down)
            d = down + sub.d
            sub_items = sub.items
        items += (sub_items + sup_items) if sub_first else (sup_items + sub_items)
        out.items, out.w, out.h, out.d = items, width, h, d
        return out
    up_shift = down_shift = 0.0
    if not nucleus.simple:
        up_shift = nucleus.h - k.sup_drop * ss
        down_shift = nucleus.d + k.sub_drop * ss
    sup_min = k.sup_text * s
    if disp:
        sup_min = k.sup_display * s
    if style & 4:
        sup_min = k.sup_cramped * s
    if sup:
        up_shift = max(up_shift, sup_min)
        up_shift = max(up_shift, sup.d + k.sup_bottom_min * s)
    if sub and not sup:
        down_shift = max(down_shift, k.sub_only * s)
        down_shift = max(down_shift, sub.h - k.sub_top_max * s)
    if sub and sup:
        down_shift = max(down_shift, k.sub_both * s)
        gap = (up_shift - sup.d) - (sub.h - down_shift)
        want = k.sub_sup_gap * s
        if gap < want:
            down_shift += want - gap
            psi = k.sup_max_with_sub * s - (up_shift - sup.d)
            if psi > 0:
                up_shift += psi
                down_shift -= psi
    corr = 0.0
    if sup and nucleus.simple and nucleus.items:
        last = nucleus.items[-1]
        corr = face.ital.get(last.get("name"), 0.0) * last["size"]
    # MathKernInfo: a one-glyph base and a one-glyph script cut into each other's corners, the base's
    # corner read at the script's near edge above the base's baseline, the script's at the base's
    # near edge above the script's baseline.
    sup_kern = sub_kern = 0.0
    if nucleus.simple and len(nucleus.items) == 1 and nucleus.items[0]["kind"] == "glyph":
        b = nucleus.items[0]
        if sup:
            sup_kern = kern_value(face, b["name"], "tr", up_shift - sup.d, b["size"])
            if sup.simple and len(sup.items) == 1 and sup.items[0]["kind"] == "glyph":
                sup_kern += kern_value(face, sup.items[0]["name"], "bl", nucleus.h - up_shift, sup.items[0]["size"])
        if sub:
            sub_kern = kern_value(face, b["name"], "br", sub.h - down_shift, b["size"])
            if sub.simple and len(sub.items) == 1 and sub.items[0]["kind"] == "glyph":
                sub_kern += kern_value(face, sub.items[0]["name"], "tl", down_shift - nucleus.d, sub.items[0]["size"])
    w, h, d = nucleus.w, nucleus.h, nucleus.d
    sp = k.script_space * s
    items = list(nucleus.items)
    if sup:
        sup.shift(nucleus.w + corr + sup_kern, -up_shift)
        w = max(w, nucleus.w + corr + sup_kern + sup.w + sp)
        h = max(h, up_shift + sup.h)
        d = max(d, sup.d - up_shift)
        items += sup.items
    if sub:
        sub.shift(nucleus.w + sub_kern, down_shift)
        w = max(w, nucleus.w + sub_kern + sub.w + sp)
        d = max(d, down_shift + sub.d)
        h = max(h, sub.h - down_shift)
        items += sub.items
    out.items, out.w, out.h, out.d = items, w, h, d
    return out


def frac(face, S, num, den, style, display):
    k = face.k
    s = S * scale(face, style)
    disp = display and (style & 3) == 0
    theta = k.rule * s
    axis = k.axis * s
    up, down = k.num_text * s, k.den_text * s
    ug, dg = k.num_gap * s, k.den_gap * s
    if disp:
        up, down = k.num_display * s, k.den_display * s
        ug, dg = k.num_gap_display * s, k.den_gap_display * s
    if (up - num.d) - (axis + theta / 2) < ug:
        up += ug - ((up - num.d) - (axis + theta / 2))
    if (axis - theta / 2) - (den.h - down) < dg:
        down += dg - ((axis - theta / 2) - (den.h - down))
    side = 0.12 * s
    width = max(num.w, den.w)
    num.shift(side + (width - num.w) / 2, -up)
    den.shift(side + (width - den.w) / 2, down)
    out = Atom(CLS_INNER)
    out.items = num.items + den.items + [dict(kind="rule", x=side, y=-(axis + theta / 2), w=width, h=theta, size=0.0, glyph=0, scalar=0)]
    out.w = width + 2 * side
    out.h = up + num.h
    out.d = down + den.d
    return out


def grown(face, scalar, need, size, cls):
    probe = glyph(face, scalar, size, cls, italic=False)
    ink = probe.h + probe.d
    if not (need > ink) or not (ink > 0):
        return probe
    name = probe.items[0]["name"]
    con = face.cons.get(name)
    if con is not None:
        for rec in con.MathGlyphVariantRecord:
            if rec.AdvanceMeasurement / face.upem * size >= need:
                a = Atom(cls)
                n = rec.VariantGlyph
                low, high = face.ext(n)
                adv = face.adv(n) * size
                a.items = [dict(kind="glyph", x=0.0, y=0.0, w=adv, h=0.0, size=size, glyph=face.gid(n), scalar=scalar, name=n)]
                a.w, a.h, a.d = adv, max(high * size, 0.0), max(-low * size, 0.0)
                return a
        if con.GlyphAssembly is not None:
            parts = con.GlyphAssembly.PartRecords
            mo = face.overlap * size
            fixed = sum(p.FullAdvance for p in parts if not p.PartFlags & 1) / face.upem * size
            ext = sum(p.FullAdvance for p in parts if p.PartFlags & 1) / face.upem * size
            next = sum(1 for p in parts if p.PartFlags & 1)
            reps = 1
            total = fixed + ext - (len(parts) - 1) * mo
            while next and total < need and reps < 64:
                reps += 1
                total = fixed + ext * reps - (len(parts) - next + next * reps - 1) * mo
            joints = len(parts) - next + next * reps - 1
            extra = (total - need) / joints if joints > 0 and total > need else 0.0
            items = []
            bottom = 0.0
            prev_end = 0.0
            placed = 0
            width = 0.0
            for p in parts:
                times = reps if p.PartFlags & 1 else 1
                for _ in range(times):
                    adv_full = p.FullAdvance / face.upem * size
                    start = p.StartConnectorLength / face.upem * size
                    if placed > 0:
                        overlap = mo + min(extra, max(min(prev_end, start) - mo, 0.0))
                        bottom -= overlap
                    n = p.glyph
                    low, high = face.ext(n)
                    adv = face.adv(n) * size
                    items.append(dict(kind="glyph", x=0.0, y=-(bottom - low * size), w=adv, h=0.0, size=size, glyph=face.gid(n), scalar=scalar, name=n))
                    width = max(width, adv)
                    bottom += adv_full
                    prev_end = p.EndConnectorLength / face.upem * size
                    placed += 1
            for it in items:
                it["x"] = (width - it["w"]) / 2
            a = Atom(cls)
            a.items, a.w, a.h, a.d = items, width, bottom, 0.0
            return a
        last = con.MathGlyphVariantRecord[-1]
        n = last.VariantGlyph
        low, high = face.ext(n)
        adv = face.adv(n) * size
        a = Atom(cls)
        a.items = [dict(kind="glyph", x=0.0, y=0.0, w=adv, h=0.0, size=size, glyph=face.gid(n), scalar=scalar, name=n)]
        a.w, a.h, a.d = adv, max(high * size, 0.0), max(-low * size, 0.0)
        return a
    return glyph(face, scalar, size * need / ink, cls, italic=False)


def grown_h(face, scalar, need, size, cls):
    """The glyph at least `need` wide: itself, the first horizontal variant whose declared advance
    reaches it, an assembly of left-to-right parts, the widest variant, else itself."""
    probe = glyph(face, scalar, size, cls, italic=False)
    if not (need > probe.w):
        return probe
    name = probe.items[0]["name"]
    con = face.hcons.get(name)
    if con is None:
        return probe

    def one(n):
        low, high = face.ext(n)
        adv = face.adv(n) * size
        a = Atom(cls)
        a.items = [dict(kind="glyph", x=0.0, y=0.0, w=adv, h=0.0, size=size, glyph=face.gid(n), scalar=scalar, name=n)]
        a.w, a.h, a.d = adv, max(high * size, 0.0), max(-low * size, 0.0)
        return a

    for rec in con.MathGlyphVariantRecord:
        if rec.AdvanceMeasurement / face.upem * size >= need:
            return one(rec.VariantGlyph)
    if con.GlyphAssembly is not None:
        parts = con.GlyphAssembly.PartRecords
        mo = face.overlap * size
        fixed = sum(p.FullAdvance for p in parts if not p.PartFlags & 1) / face.upem * size
        ext = sum(p.FullAdvance for p in parts if p.PartFlags & 1) / face.upem * size
        n_ext = sum(1 for p in parts if p.PartFlags & 1)
        reps = 1
        total = fixed + ext - (len(parts) - 1) * mo
        while n_ext and total < need and reps < 64:
            reps += 1
            total = fixed + ext * reps - (len(parts) - n_ext + n_ext * reps - 1) * mo
        joints = len(parts) - n_ext + n_ext * reps - 1
        extra = (total - need) / joints if joints > 0 and total > need else 0.0
        items = []
        pen = 0.0
        prev_end = 0.0
        placed = 0
        top = bottom = 0.0
        for p in parts:
            for _ in range(reps if p.PartFlags & 1 else 1):
                adv_full = p.FullAdvance / face.upem * size
                start = p.StartConnectorLength / face.upem * size
                if placed > 0:
                    pen -= mo + min(extra, max(min(prev_end, start) - mo, 0.0))
                piece = one(p.glyph)
                piece.items[0]["x"] = pen
                items += piece.items
                top = max(top, piece.h)
                bottom = max(bottom, piece.d)
                pen += adv_full
                prev_end = p.EndConnectorLength / face.upem * size
                placed += 1
        a = Atom(cls)
        a.items, a.w, a.h, a.d = items, pen, top, bottom
        return a
    if con.MathGlyphVariantRecord:
        return one(con.MathGlyphVariantRecord[-1].VariantGlyph)
    return probe


def accent(face, base, scalar, wide, below, size):
    """An accent over (or under) `base`: attachment points aligned, raised by the base's height
    over AccentBaseHeight."""
    acc = grown_h(face, scalar, base.w, size, CLS_ORD) if wide else glyph(face, scalar, size, CLS_ORD, italic=False)
    base_attach = base.w / 2
    if len(base.items) == 1 and base.items[0]["kind"] == "glyph":
        it = base.items[0]
        if it["name"] in face.top_attach:
            base_attach = face.top_attach[it["name"]] * it["size"]
    acc_attach = acc.w / 2
    if len(acc.items) == 1 and acc.items[0]["name"] in face.top_attach:
        acc_attach = face.top_attach[acc.items[0]["name"]] * size
    lift = drop = 0.0
    if below:
        drop = base.d + face.k.under_gap * size + acc.h
    else:
        lift = max(0.0, base.h - face.k.accent_base * size)
    acc.shift(base_attach - acc_attach, drop - lift)
    out = Atom(CLS_ORD)
    out.items = base.items + acc.items
    out.w, out.h, out.d = base.w, base.h, base.d
    if below:
        out.d = max(base.d, drop + acc.d)
    else:
        out.h = max(base.h, lift + acc.h)
    return out


def bar(face, body, size, over):
    k = face.k
    out = Atom(CLS_ORD)
    out.w, out.h, out.d = body.w, body.h, body.d
    if over:
        gap, thick = k.over_gap * size, k.over_rule * size
        rule = dict(kind="rule", x=0.0, y=-(body.h + gap + thick), w=body.w, h=thick, size=0.0, glyph=0, scalar=0)
        out.h = body.h + gap + thick + k.over_extra * size
    else:
        gap, thick = k.under_gap * size, k.under_rule * size
        rule = dict(kind="rule", x=0.0, y=body.d + gap, w=body.w, h=thick, size=0.0, glyph=0, scalar=0)
        out.d = body.d + gap + thick + k.under_extra * size
    out.items = body.items + [rule]
    return out


def brace(face, body, size, over):
    k = face.k
    brace_atom = grown_h(face, 0x23DE if over else 0x23DF, body.w, size, CLS_ORD)
    centre = (max(body.w, brace_atom.w) - brace_atom.w) / 2
    out = Atom(CLS_OP)
    out.w, out.h, out.d = body.w, body.h, body.d
    if over:
        gap = k.stretch_below * size
        brace_atom.shift(centre, -(body.h + gap + brace_atom.d))
        out.h = body.h + gap + brace_atom.d + brace_atom.h
    else:
        gap = k.stretch_above * size
        brace_atom.shift(centre, body.d + gap + brace_atom.h)
        out.d = body.d + gap + brace_atom.h + brace_atom.d
    if brace_atom.w > body.w:
        body.shift((brace_atom.w - body.w) / 2, 0.0)
    out.w = max(body.w, brace_atom.w)
    out.items = body.items + brace_atom.items
    out.limits = True
    out.stretch = True
    return out


def delimiter(face, scalar, span, size, cls):
    if scalar == 0:
        return Atom(cls)
    g = grown(face, scalar, span, size, cls)
    lift = face.k.axis * size - (g.h - g.d) / 2
    g.shift(0.0, -lift)
    g.h += lift
    g.d -= lift
    return g


def fence(face, S, body, left, right, style):
    s = S * scale(face, style)
    axis = face.k.axis * s
    delta = max(body.h - axis, body.d + axis)
    span = max(2 * delta * 0.95, face.k.delim_min * s)
    l = delimiter(face, left, span, s, CLS_OPEN)
    body.shift(l.w, 0.0)
    r = delimiter(face, right, span, s, CLS_CLOSE)
    r.shift(l.w + body.w, 0.0)
    out = Atom(CLS_INNER)
    out.items = body.items + l.items + r.items
    out.w = l.w + body.w + r.w
    out.h = max(body.h, l.h, r.h)
    out.d = max(body.d, l.d, r.d)
    return out


def radical(face, S, body, index, style, display):
    k = face.k
    s = S * scale(face, style)
    theta = k.rad_rule * s
    clearance = k.rad_gap * s
    if display and (style & 3) == 0:
        clearance = k.rad_gap_display * s
    need = body.h + body.d + clearance + theta
    sign = grown(face, 0x221A, need, s, CLS_ORD)
    top = body.h + clearance + theta
    sign.shift(0.0, -(top - sign.h))
    sign_x = index_x = 0.0
    if index is not None:
        index_x = max(k.rad_before * s, 0.0)
        sign_x = max(index_x + index.w + k.rad_after * s, 0.0)
        raise_by = k.rad_raise * (top + body.d) - body.d
        index.shift(index_x, -raise_by)
    sign.shift(sign_x, 0.0)
    body.shift(sign_x + sign.w, 0.0)
    out = Atom()
    out.items = (index.items if index is not None else []) + body.items + sign.items + [dict(kind="rule", x=sign_x + sign.w, y=-top, w=body.w, h=theta, size=0.0, glyph=0, scalar=0)]
    out.w = sign_x + sign.w + body.w
    out.h = top + k.rad_extra * s
    out.d = max(body.d, sign.d - (top - sign.h))
    if index is not None:
        out.h = max(out.h, k.rad_raise * (top + body.d) - body.d + index.h)
    return out


def big_op(face, S, scalar, style, display):
    k = face.k
    s = S * scale(face, style)
    big = display and (style & 3) == 0
    if big and k.op_min > 0:
        op = grown(face, scalar, k.op_min * s, s, CLS_OP)
    elif big:
        op = glyph(face, scalar, s * 1.4, CLS_OP, italic=False)
    else:
        op = glyph(face, scalar, s, CLS_OP, italic=False)
    lift = k.axis * s - (op.h - op.d) / 2
    op.shift(0.0, -lift)
    op.h += lift
    op.d -= lift
    op.simple = False
    op.limits = True
    return op


def g(face, ch, S, style, cls=None, italic=True, alphabet=None):
    c = ord(ch)
    if cls is None:
        cls = {"+": CLS_BIN, "=": CLS_REL, "(": CLS_OPEN, ")": CLS_CLOSE, ",": CLS_PUNCT}.get(ch, CLS_ORD)
    return glyph(face, c, S * scale(face, style), cls, italic, alphabet)


def finish(a):
    return dict(items=a.items, width=a.w, ascent=a.h, descent=a.d)


def tuple_row(face, S, atoms, style):
    return row(face, S, atoms, style)


# ---- the cases ---------------------------------------------------------------------------------

def align_env(face, S, rows, style):
    """`align`: columns alternate right and left, pairs an em apart; cells are atoms."""
    s = S * scale(face, style)
    cols = max(len(r) for r in rows)
    col_w = [0.0] * cols
    row_h = [0.84 * s] * len(rows)
    row_d = [0.36 * s] * len(rows)
    for r, cells in enumerate(rows):
        for c, a in enumerate(cells):
            col_w[c] = max(col_w[c], a.w)
            row_h[r] = max(row_h[r], a.h)
            row_d[r] = max(row_d[r], a.d)
    total_h = sum(h + d for h, d in zip(row_h, row_d))
    col_x = []
    x = 0.0
    for c in range(cols):
        col_x.append(x)
        x += col_w[c]
        if c + 1 < cols:
            x += 0.0 if c % 2 == 0 else s
    top = face.k.axis * s + total_h / 2
    out = Atom(CLS_INNER)
    for r, cells in enumerate(rows):
        above = top - sum(row_h[i] + row_d[i] for i in range(r)) - row_h[r]
        for c, a in enumerate(cells):
            px = col_x[c] + ((col_w[c] - a.w) if c % 2 == 0 else 0.0)
            a.shift(px, -above)
            out.items += a.items
    out.w = x
    out.h = top
    out.d = total_h - top
    return out


def model_cases(M, P):
    S = 20.0
    cases = []

    def add(label, face, mode, src, atom, size=S):
        cases.append(dict(label=label, face=face, mode=mode, src=src, result=finish(atom), size=size))

    t = 1
    add("two italic letters", M, "L", "ax", row(M, S, [g(M, "a", S, t), g(M, "x", S, t)], t))
    add("superscript after an italic correction", M, "L", "x^2",
        scripts(M, S, g(M, "x", S, t), g(M, "2", S, 2), None, t, False))
    num = g(M, "1", S, 2)
    den = scripts(M, S, g(M, "x", S, 6), g(M, "2", S, 7), None, 6, False)
    add("superscript in a cramped denominator", M, "L", r"\frac{1}{x^2}", frac(M, S, num, den, t, False))
    num = scripts(M, S, g(M, "x", S, 2), g(M, "2", S, 3), None, 2, False)
    add("the same superscript in the numerator, not cramped", M, "L", r"\frac{x^2}{1}", frac(M, S, num, g(M, "1", S, 6), t, False))
    add("radical, natural sign", M, "L", r"\sqrt{x}", radical(M, S, g(M, "x", S, 5), None, t, False))
    body = scripts(M, S, g(M, "x", S, 5), g(M, "2", S, 6), None, 5, False)
    add("radical, first variant tall enough", M, "L", r"\sqrt{x^2}", radical(M, S, body, None, t, False))
    add("radical with an index", M, "L", r"\sqrt[3]{x}", radical(M, S, g(M, "x", S, 5), g(M, "3", S, 3), t, False))
    body = frac(M, S, g(M, "a", S, 6), g(M, "b", S, 6), 5, False)
    add("radical over a fraction, taller variant", M, "L", r"\sqrt{\frac{a}{b}}", radical(M, S, body, None, t, False))
    body = row(M, S, [frac(M, S, g(M, "a", S, 2), g(M, "b", S, 6), t, False)], t)
    add("parenthesis assembly", M, "L", r"\left(\frac{a}{b}\right)", fence(M, S, body, 40, 41, t))
    num_inner = frac(M, S, g(M, "a", S, 3), g(M, "b", S, 7), 2, False)
    den_inner = frac(M, S, g(M, "a", S, 7), g(M, "b", S, 7), 6, False)
    body = row(M, S, [frac(M, S, num_inner, den_inner, t, False)], t)
    add("parenthesis assembly, tall", M, "L", r"\left(\frac{\frac{a}{b}}{\frac{a}{b}}\right)", fence(M, S, body, 40, 41, t))
    op = big_op(M, S, 0x2211, 0, True)
    add("display operator with limits", M, "D", r"\sum_{a}^{b}",
        scripts(M, S, op, g(M, "b", S, 2), g(M, "a", S, 6), 0, True, sub_first=True))
    add("text fraction", M, "L", r"\frac{a}{b}", frac(M, S, g(M, "a", S, 2), g(M, "b", S, 6), t, False))
    add("display fraction", M, "D", r"\frac{a}{b}", frac(M, S, g(M, "a", S, 1), g(M, "b", S, 5), 0, True))
    add("display radical", M, "D", r"\sqrt{x}", radical(M, S, g(M, "x", S, 4), None, 0, True))
    # D3702: alphabets.
    R = lambda *atoms: row(M, S, list(atoms), t)
    A = lambda ch, alpha: g(M, ch, S, t, alphabet=alpha)
    add("bold letters", M, "L", r"\mathbf{ax}", R(R(A("a", "bold"), A("x", "bold"))))
    add("script capitals, B from Letterlike Symbols", M, "L", r"\mathcal{AB}", R(R(A("A", "script"), A("B", "script"))))
    add("double-struck and fraktur holes", M, "L", r"\mathbb{RC}\mathfrak{AC}",
        R(R(A("R", "double"), A("C", "double")), R(A("A", "fraktur"), A("C", "fraktur"))))
    add("sans, mono, bold italic, digits and a Greek letter", M, "L",
        r"\mathsf{a}\mathtt{a}\boldsymbol{a}\mathbf{1}\mathtt{2}\mathbf{\alpha}",
        R(R(A("a", "sans")), R(A("a", "mono")), R(A("a", "bold_italic")), R(A("1", "bold")), R(A("2", "mono")),
          R(A(chr(945), "bold"))))
    add("a letter the alphabet's block lacks stays itself", M, "L", r"\mathbf{c}", R(R(A("c", "bold"))))
    # Accents.
    cr = 5
    add("hat over a letter with an attachment point", M, "L", r"\hat{x}",
        R(accent(M, g(M, "x", S, cr), 0x302, False, False, S)))
    add("tilde over a letter with an attachment point", M, "L", r"\tilde{a}",
        R(accent(M, g(M, "a", S, cr), 0x303, False, False, S)))
    add("bar over a letter with none, and a script after it", M, "L", r"\bar{y}^{2}",
        scripts(M, S, accent(M, g(M, "y", S, cr), 0x304, False, False, S), g(M, "2", S, 2), None, t, False))
    add("dot over a row", M, "L", r"\dot{ab}",
        R(accent(M, row(M, S, [g(M, "a", S, cr), g(M, "b", S, cr)], cr), 0x307, False, False, S)))
    add("vector arrow", M, "L", r"\vec{x}", R(accent(M, g(M, "x", S, cr), 0x20D7, False, False, S)))
    add("wide hat takes the widest variant", M, "L", r"\widehat{xax}",
        R(accent(M, row(M, S, [g(M, "x", S, cr), g(M, "a", S, cr), g(M, "x", S, cr)], cr), 0x302, True, False, S)))
    add("wide hat takes the first variant that reaches", M, "L", r"\widehat{x}",
        R(accent(M, g(M, "x", S, cr), 0x302, True, False, S)))
    add("wide tilde", M, "L", r"\widetilde{ab}",
        R(accent(M, row(M, S, [g(M, "a", S, cr), g(M, "b", S, cr)], cr), 0x303, True, False, S)))
    # Bars and braces.
    add("overline", M, "L", r"\overline{x}", R(bar(M, g(M, "x", S, cr), S, True)))
    add("underline", M, "L", r"\underline{ab}", R(bar(M, row(M, S, [g(M, "a", S, t), g(M, "b", S, t)], t), S, False)))
    add("overbrace assembled from parts", M, "L", r"\overbrace{xaxaxa}",
        R(brace(M, row(M, S, [g(M, c, S, t) for c in "xaxaxa"], t), S, True)))
    add("overbrace with a label placed as an upper limit", M, "L", r"\overbrace{ab}^{x}",
        scripts(M, S, brace(M, row(M, S, [g(M, "a", S, t), g(M, "b", S, t)], t), S, True), g(M, "x", S, 2), None, t, False))
    add("underbrace with a label placed as a lower limit", M, "L", r"\underbrace{ab}_{x}",
        scripts(M, S, brace(M, row(M, S, [g(M, "a", S, t), g(M, "b", S, t)], t), S, False), None, g(M, "x", S, 6), t, False))
    # MathKernInfo.
    add("superscript kerned by the base's top right and the script's bottom left", M, "L", r"x^y",
        scripts(M, S, g(M, "x", S, t), g(M, "y", S, 2), None, t, False))
    add("superscript on a base with only a top right table", M, "L", r"a^b",
        scripts(M, S, g(M, "a", S, t), g(M, "b", S, 2), None, t, False))
    add("subscript kerned by the base's bottom right and the script's top left", M, "L", r"x_y",
        scripts(M, S, g(M, "x", S, t), None, g(M, "y", S, 6), t, False))
    add("both scripts, display style", M, "D", r"x^y_y",
        scripts(M, S, g(M, "x", S, 0), g(M, "y", S, 2), g(M, "y", S, 6), 0, True))
    # `align` over the plain font, display style.
    a = lambda ch: g(P, ch, S, 0)
    rows = [
        [row(P, S, [a("a")], 0), row(P, S, [a("="), a("b")], 0)],
        [row(P, S, [a("c"), a("c")], 0), row(P, S, [a("="), a("d")], 0)],
    ]
    cases.append(dict(label="align, two rows", face=P, mode="D", src=r"\begin{align}a&=b\\cc&=d\end{align}",
                      result=finish(align_env(P, S, rows, 0)), size=S))
    return cases


def check_code(cases, first_code):
    """Neper statements: one function per case, each answering the check that failed."""
    out = []
    code = first_code
    for i, case in enumerate(cases):
        r = case["result"]
        fn = "check_model_%d" % i
        lines = ["// %s: %s" % (case["label"], case["src"]),
                 "fn %s(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {" % fn]
        lines.append("    let options = math.Options { font: font, size: %s, display: %s, notdef: false }" % (fnum(case["size"]), "true" if case["mode"] == "D" else "false"))
        src = case["src"].replace("\\", "\\\\")
        lines.append("    let (eq, eq_error) = math.typeset(a, \"%s\", options, items)" % src)
        # One code a case (an exit status may keep eight bits); `bad` says which check on stdout.
        why = "check %d (%s): " % (code, case["src"].replace("\\", "\\\\"))
        lines.append("    if eq_error != ok { ret bad(%di32, \"%stypeset refused\\n\") }" % (code, why))
        lines.append("    if eq.items.len != %dusize { ret bad(%di32, \"%sitem count\\n\") }" % (len(r["items"]), code, why))
        lines.append("    if !near(eq.width, %s, 0.02) || !near(eq.ascent, %s, 0.02) || !near(eq.descent, %s, 0.02) { ret bad(%di32, \"%sextent\\n\") }" % (fnum(r["width"]), fnum(r["ascent"]), fnum(r["descent"]), code, why))
        for k, it in enumerate(r["items"]):
            if it["kind"] == "rule":
                lines.append("    if !is_rule(eq.items[%dusize], %s, %s, %s, %s) { ret bad(%di32, \"%srule %d\\n\") }" % (k, fnum(it["x"]), fnum(it["y"]), fnum(it["w"]), fnum(it["h"]), code, why, k))
            else:
                lines.append("    if !is_glyph(eq.items[%dusize], %s, %s, %s, %du32, %du32) { ret bad(%di32, \"%sglyph %d\\n\") }" % (k, fnum(it["x"]), fnum(it["y"]), fnum(it["size"]), it["scalar"], it["glyph"], code, why, k))
        lines += ["    ret 0i32", "}", ""]
        out.append(("\n".join(lines), fn, code))
        code += 1
    return out


def fnum(v):
    s = "%.4f" % v
    if s.startswith("-"):
        return "(0.0 - %s)" % s[1:]
    return s


MATHML_PAIRS = [
    ("sum of letters", "L", "<math><mrow><mi>a</mi><mo>+</mo><mi>x</mi></mrow></math>", "a+x"),
    ("superscript", "L", "<math><msup><mi>x</mi><mn>2</mn></msup></math>", "x^2"),
    ("subscript and superscript", "L", "<math><msubsup><mi>x</mi><mn>1</mn><mn>2</mn></msubsup></math>", "x_1^2"),
    ("fraction", "L", "<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>", "\\frac{a}{b}"),
    ("fraction of rows", "L", "<math><mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mn>12</mn></mfrac></math>", "\\frac{a+b}{12}"),
    ("square root", "L", "<math><msqrt><mi>x</mi></msqrt></math>", "\\sqrt{x}"),
    ("root with an index", "L", "<math><mroot><mi>x</mi><mn>3</mn></mroot></math>", "\\sqrt[3]{x}"),
    ("fenced list", "L", "<math><mfenced open=\"(\" close=\")\"><mi>a</mi><mi>b</mi></mfenced></math>", "\\left(a,b\\right)"),
    ("summation with limits", "D", "<math><munderover><mo>&#x2211;</mo><mi>a</mi><mi>b</mi></munderover></math>", "\\sum_{a}^{b}"),
    ("table", "L", "<math><mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable></math>", "\\begin{matrix}a&b\\\\x&y\\end{matrix}"),
    ("function name and entity", "L", "<math><mi>sin</mi><mo>&#x2061;</mo><mi>x</mi><mo>&#x2212;</mo><mn>1</mn></math>", "\\sin x-1"),
    ("text", "L", "<math><mtext>if</mtext><mi>x</mi></math>", "\\text{if}x"),
    ("accented mover", "L", "<math><mover accent=\"true\"><mi>x</mi><mo>^</mo></mover></math>", "\\overaccent{^}{x}"),
    ("accent from the operator without the attribute", "L", "<math><mover><mi>x</mi><mo>&#x303;</mo></mover></math>", "\\overaccent{\u0303}{x}"),
    ("under accent", "L", "<math><munder accentunder=\"true\"><mrow><mi>a</mi><mi>b</mi></mrow><mo>~</mo></munder></math>", "\\underaccent{~}{ab}"),
    ("over brace", "L", "<math><mover><mrow><mi>a</mi><mi>b</mi></mrow><mo>&#x23DE;</mo></mover></math>", "\\overbrace{ab}"),
    ("under brace", "L", "<math><munder><mrow><mi>a</mi><mi>b</mi></mrow><mo>&#x23DF;</mo></munder></math>", "\\underbrace{ab}"),
    ("a letter over is a script, not an accent", "L", "<math><mover><mi>x</mi><mi>y</mi></mover></math>", "x^y"),
]
MATHML_REFUSED = [
    "<math><mi>a</mi>",
    "<math><mfoo/></math>",
    "<math><mi>a</mi></mrow>",
    "<math><mo>&bogus;</mo></math>",
    "<math><mi>a</mi></math>trailing",
]

HELPERS = r'''fn math_font_path() -> str {
    ret "tests/selfhost/fixtures/link/text_math/assets/mathfont.ttf"
}

// A failed check: its code, after saying which check on stdout.
fn bad(code: i32, why: str) -> i32 {
    let said = io.print(why)
    ret code
}

fn is_glyph(item: math.Item, x: f32, y: f32, size: f32, scalar: u32, glyph: u32) -> bool {
    ret item.kind == .Glyph && near(item.x, x, 0.02) && near(item.y, y, 0.02) && near(item.size, size, 0.001) && item.scalar == scalar && item.glyph == glyph
}

fn is_rule(item: math.Item, x: f32, y: f32, w: f32, h: f32) -> bool {
    ret item.kind == .Rule && near(item.x, x, 0.02) && near(item.y, y, 0.02) && near(item.w, w, 0.02) && near(item.h, h, 0.02)
}

// Are two typesettings the same item for item, to the bit?
fn same_equation(left: math.Equation, right: math.Equation) -> bool {
    if left.items.len != right.items.len || left.width != right.width || left.ascent != right.ascent || left.descent != right.descent { ret false }
    var i = 0usize
    while i < left.items.len {
        let l = left.items[i]
        let r = right.items[i]
        if l.kind != r.kind || l.x != r.x || l.y != r.y || l.w != r.w || l.h != r.h || l.size != r.size || l.glyph != r.glyph || l.scalar != r.scalar { ret false }
        i += 1usize
    }
    ret true
}

// Presentation MathML typesets as the LaTeX it translates to, item for item.
fn check_pair(a: *mem.Arena, font: shape.Font, display: bool, mathml: str, latex: str, code: i32) -> i32 {
    let options = math.Options { font: font, size: 20.0, display: display, notdef: false }
    let (first, first_items_error) = mem.alloc[math.Item](a, 128usize)
    if first_items_error != ok { ret code }
    let (second, second_items_error) = mem.alloc[math.Item](a, 128usize)
    if second_items_error != ok { ret code }
    let (from_ml, ml_error) = math.typeset_mathml(a, mathml, options, first)
    if ml_error != ok { ret code }
    let (from_tex, tex_error) = math.typeset(a, latex, options, second)
    if tex_error != ok { ret code + 1i32 }
    if from_ml.items.len == 0usize || !same_equation(from_ml, from_tex) { ret code + 2i32 }
    ret 0i32
}

const DRAW_SIDE_W: usize = 96usize
const DRAW_SIDE_H: usize = 48usize

// `\frac{a}{b}+\sqrt{x}` drawn through the scene's CPU backend, 4 x 4 cell means against
// Pillow's 8x supersampled rendering of the same items.
fn check_draw(a: *mem.Arena, font: shape.Font, items: []math.Item) -> i32 {
    let options = math.Options { font: font, size: 22.0, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}+\\sqrt{x}", options, items)
    if eq_error != ok { ret 230i32 }
    let (text_layout, layout_error) = math.to_layout(a, eq, font)
    if layout_error != ok { ret 231i32 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret 232i32 }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret 233i32 }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(DRAW_SIDE_W), u32(DRAW_SIDE_H), gpu.Format.Bgra8)
    if frames_error != ok { ret 234i32 }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret 235i32 }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret 236i32 }
    var renderer = renderer_value
    if scene.register_font(&renderer, font) != ok { ret 237i32 }
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret 238i32 }
    var builder = builder_value
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    let black = paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 96.0, 48.0), brush: paint.Brush { Solid: white } } }) != ok { ret 239i32 }
    let origin = geometry.Point { x: @@OX@@, y: @@OY@@ }
    if scene.push(&builder, scene.Command { Text: scene.DrawText { layout: &text_layout, origin: origin, brush: paint.Brush { Solid: black } } }) != ok { ret 240i32 }
    var rules = 0usize
    var k = 0usize
    while k < eq.items.len {
        let item = eq.items[k]
        if item.kind == .Rule {
            rules += 1usize
            if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(origin.x + item.x, origin.y + item.y, item.w, item.h), brush: paint.Brush { Solid: black } } }) != ok { ret 241i32 }
        }
        k += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret 242i32 }
    if scene.render(&renderer, scene_id, canvas, geometry.Size { width: 96.0, height: 48.0 }) != ok { ret 243i32 }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret 244i32 }
    let (pixels, pixels_error) = mem.alloc[u32](a, DRAW_SIDE_W * DRAW_SIDE_H)
    if pixels_error != ok { ret 245i32 }
    if gpu.read_image(q, image, pixels) != ok { ret 246i32 }
    let want = DRAW_CELLS
    var total = 0i64
    var worst = 0i32
    var cy = 0usize
    while cy < DRAW_SIDE_H / 4usize {
        var cx = 0usize
        while cx < DRAW_SIDE_W / 4usize {
            var sum = 0u32
            var y = 0usize
            while y < 4usize {
                var x = 0usize
                while x < 4usize {
                    sum += pixels[(cy * 4usize + y) * DRAW_SIDE_W + cx * 4usize + x] & 255u32
                    x += 1usize
                }
                y += 1usize
            }
            var diff = i32(sum / 16u32) - i32(want[cy * (DRAW_SIDE_W / 4usize) + cx])
            if diff < 0i32 { diff = 0i32 - diff }
            total += i64(diff)
            if diff > worst { worst = diff }
            cx += 1usize
        }
        cy += 1usize
    }
    let cells = (DRAW_SIDE_W / 4usize) * (DRAW_SIDE_H / 4usize)
    if f32(total) / f32(cells) > 3.0 { ret 247i32 }
    if worst > 70i32 { ret 248i32 }
    // A rule item is a rectangle and every other item is a glyph run of its own.
    if text_layout.lines.len != 1usize || text_layout.lines[0usize].runs.len + rules != eq.items.len { ret 249i32 }
    ret 0i32
}
'''


def draw_reference(face_path, size, source_items, ox, oy, width=96, height=48, ss=8):
    big = Image.new("L", (width * ss, height * ss), 255)
    d = ImageDraw.Draw(big)
    fonts = {}
    for it in source_items:
        if it["kind"] == "rule":
            d.rectangle([(ox + it["x"]) * ss, (oy + it["y"]) * ss, (ox + it["x"] + it["w"]) * ss - 1, (oy + it["y"] + it["h"]) * ss - 1], fill=0)
        else:
            sz = it["size"]
            if sz not in fonts:
                fonts[sz] = ImageFont.truetype(face_path, sz * ss, layout_engine=ImageFont.Layout.BASIC)
            d.text(((ox + it["x"]) * ss, (oy + it["y"]) * ss), chr(it["scalar"]), font=fonts[sz], fill=0, anchor="ls")
    small = big.resize((width, height), Image.BOX)
    px = small.load()
    cells = []
    for cy in range(height // 4):
        for cx in range(width // 4):
            s = 0
            for y in range(4):
                for x in range(4):
                    s += px[cx * 4 + x, cy * 4 + y]
            cells.append(s // 16)
    return cells


def neper_bytes(data):
    return "".join("\\x%02x" % b for b in data)


def generate(P, M):
    cases = model_cases(M, P)
    code_funcs = check_code(cases, 100)
    # The drawing reference uses the plain font's own model of the same expression.
    S = 22.0
    plain = lambda ch, style: g(P, ch, S, style)
    num, den = plain("a", 2), plain("b", 6)
    parts = [frac(P, S, num, den, 1, False), plain("+", 1), radical(P, S, plain("x", 5), None, 1, False)]
    drawn = finish(row(P, S, parts, 1))
    ox, oy = 8.0, 30.0
    cells = draw_reference(PLAIN_FONT, S, drawn["items"], ox, oy)
    out = [HELPERS.replace("@@OX@@", "%.1f" % ox).replace("@@OY@@", "%.1f" % oy)]
    out[0] = out[0].replace("let want = DRAW_CELLS", 'let want = "%s"' % neper_bytes(cells))
    for text, fn, _ in code_funcs:
        out.append(text)
    lines = ["fn check_extra(a: *mem.Arena, items: []math.Item, plain: shape.Font, math_font: shape.Font) -> i32 {",
             "    var failed = 0i32"]
    for (text, fn, code), case in zip(code_funcs, cases):
        which = "plain" if case["face"] is P else "math_font"
        lines.append("    failed = %s(a, items, %s)" % (fn, which))
        lines.append("    if failed != 0i32 { ret failed }")
    code = 160
    for label, mode, ml, tex in MATHML_PAIRS:
        ml_s = ml.replace("\\", "\\\\").replace('"', '\\"')
        tex_s = tex.replace("\\", "\\\\")
        lines.append("    // MathML: %s." % label)
        lines.append("    failed = check_pair(a, math_font, %s, \"%s\", \"%s\", %di32)" % ("true" if mode == "D" else "false", ml_s, tex_s, code))
        lines.append("    if failed != 0i32 { ret failed }")
        code += 3
    lines.append("    // MathML that is not well formed or not in the subset is refused.")
    for k, refused in enumerate(MATHML_REFUSED):
        bad_s = refused.replace("\\", "\\\\").replace('"', '\\"')
        lines.append("    let (_, refused_%d) = math.typeset_mathml(a, \"%s\", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)" % (k, bad_s))
        lines.append("    if refused_%d != math.Invalid { ret %di32 }" % (k, code + k))
    code += len(MATHML_REFUSED)
    lines.append("    // The scene draws the equation.")
    lines.append("    failed = check_draw(a, plain, items)")
    lines.append("    if failed != 0i32 { ret failed }")
    lines += ["    ret 0i32", "}", ""]
    out.append("\n".join(lines))
    return "\n".join(out), drawn, cells


def write_fixture(block):
    text = open(MAIN, encoding="utf-8").read()
    begin = "// @@GENERATED-BEGIN (scripts/gen_math_render_test.py) @@\n"
    end = "// @@GENERATED-END @@\n"
    if begin not in text:
        raise SystemExit("markers missing from main.e")
    a = text.index(begin) + len(begin)
    b = text.index(end)
    open(MAIN, "w", encoding="utf-8", newline="\n").write(text[:a] + block + text[b:])


if __name__ == "__main__":
    M = Face(MATH_FONT)
    P = Face(PLAIN_FONT)
    block, drawn, cells = generate(P, M)
    write_fixture(block)
    print("wrote the generated section of", MAIN, "(%d draw cells, %d model cases)" % (len(cells), len(model_cases(M, P))))
