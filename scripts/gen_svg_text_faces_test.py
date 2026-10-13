"""Writes tests/selfhost/fixtures/link/gfx_svg_text_faces (L125, D4504).

`font-family`, `font-weight` and `<textPath>` in e.gfx.svg, against Pillow's FreeType rasteriser over the same
font files (Jost and Exo 2, the repository's OFL faces), as scripts/gen_svg_text_test.py does for plain text: each
document is drawn by Pillow at 8x on white at the positions the SVG rules give and box-reduced to 24 x 12 cells.

 * Faces: the fixture offers four -- "Jost" (400), "Exo 2" (400), and "Mixed" at 400 (Jost) and 700 (Exo 2) --
   so a case names the face it expects by file, and weight selection is visible even though neither file has
   a bold: family lists with quotes and different case, nearest weight, keywords, inherited and `style` values,
   an unknown family falling to the first face.
 * Text on a path: each character is drawn on its own layer at the point of the path where its middle falls
   (the advance of the text before it from the face's own metrics, so kerning counts), rotated to the tangent
   there. The paths are lines, a semicircle sampled by angle and a quadratic sampled by parameter here -- not the
   renderer's flattening -- so the oracle owns the geometry.

    python scripts/gen_svg_text_faces_test.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOST = os.path.join(ROOT, "neperos", "assets", "fonts", "jost-regular.ttf")
EXO = os.path.join(ROOT, "neperos", "assets", "fonts", "exo2-regular.ttf")
W, H, SS = 96, 48, 8
CW, CH = W // 4, H // 4
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 96 48">'


def plain(x, y, size, text, font, fill=(0, 0, 0), anchor="start"):
    return dict(kind="plain", x=x, y=y, size=size, text=text, font=font, fill=fill, anchor=anchor)


def on_path(points, size, text, font, begin=0.0, anchor="start", fill=(0, 0, 0)):
    return dict(kind="path", points=points, size=size, text=text, font=font, begin=begin, anchor=anchor, fill=fill)


def line(x0, y0, x1, y1, n=200):
    return [(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n) for i in range(n + 1)]


def arc(cx, cy, r, a0, a1, n=400):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def quad(p0, p1, p2, n=400):
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return out


CASES = [
    ("family by name", HEAD + '<text x="4" y="30" font-size="20" font-family="Exo 2">Exo</text></svg>', [plain(4, 30, 20, "Exo", EXO)]),
    ("a family list: unknown first, quoted, other case",
     HEAD + '<text x="4" y="30" font-size="20" font-family="Nope, \'JOST\'">Jost</text></svg>', [plain(4, 30, 20, "Jost", JOST)]),
    ("weight 700 picks the bold face of a family",
     HEAD + '<text x="4" y="30" font-size="20" font-family="Mixed" font-weight="bold">Bold</text></svg>', [plain(4, 30, 20, "Bold", EXO)]),
    ("weight 300 takes the nearest, 400",
     HEAD + '<text x="4" y="30" font-size="20" font-family="Mixed" font-weight="300">Light</text></svg>', [plain(4, 30, 20, "Light", JOST)]),
    ("weight 600 is nearer 700 than 400",
     HEAD + '<text x="4" y="30" font-size="20" font-family="Mixed" font-weight="600">Semi</text></svg>', [plain(4, 30, 20, "Semi", EXO)]),
    ("normal is 400", HEAD + '<text x="4" y="30" font-size="20" font-family="Mixed" font-weight="normal">Norm</text></svg>', [plain(4, 30, 20, "Norm", JOST)]),
    ("family and weight inherit from a group",
     HEAD + '<g font-family="Mixed" font-weight="700"><text x="4" y="20" font-size="14">One</text><text x="4" y="40" font-size="14" font-weight="400">Two</text></g></svg>',
     [plain(4, 20, 14, "One", EXO), plain(4, 40, 14, "Two", JOST)]),
    ("a style declaration", HEAD + '<text x="4" y="30" font-size="20" style="font-family:Exo 2;font-weight:700">Style</text></svg>', [plain(4, 30, 20, "Style", EXO)]),
    ("an unknown family falls to the first face",
     HEAD + '<text x="4" y="30" font-size="20" font-family="Nowhere, serif">Fall</text></svg>', [plain(4, 30, 20, "Fall", JOST)]),
    ("text on a line, with an offset",
     HEAD + '<defs><path id="p" d="M6 38 L90 38"/></defs><text font-size="16" font-family="Jost"><textPath xlink:href="#p" startOffset="4">Along</textPath></text></svg>',
     [on_path(line(6, 38, 90, 38), 16, "Along", JOST, begin=4)]),
    ("text on a semicircle",
     HEAD + '<defs><path id="p" d="M18 42 A30 30 0 0 1 78 42"/></defs><text font-size="12" font-family="Exo 2"><textPath href="#p">Round the arc</textPath></text></svg>',
     [on_path(arc(48, 42, 30, math.pi, 2 * math.pi), 12, "Round the arc", EXO)]),
    ("middle anchor at half of the path",
     HEAD + '<defs><path id="p" d="M6 30 L90 30"/></defs><text font-size="14" text-anchor="middle"><textPath xlink:href="#p" startOffset="50%">Centred</textPath></text></svg>',
     [on_path(line(6, 30, 90, 30), 14, "Centred", JOST, begin=42, anchor="middle")]),
    ("characters past the end of the path are dropped",
     HEAD + '<defs><path id="p" d="M4 24 L40 24"/></defs><text font-size="14"><textPath xlink:href="#p">This is far too long</textPath></text></svg>',
     [on_path(line(4, 24, 40, 24), 14, "This is far too long", JOST)]),
    ("text on a quadratic curve",
     HEAD + '<defs><path id="p" d="M6 40 Q48 -6 90 40"/></defs><text font-size="13" fill="#a02020"><textPath xlink:href="#p">Curved text here</textPath></text></svg>',
     [on_path(quad((6, 40), (48, -6), (90, 40)), 13, "Curved text here", JOST, fill=(160, 32, 32))]),
]


def reference(draws):
    im = Image.new("RGB", (W * SS, H * SS), (255, 255, 255))
    d = ImageDraw.Draw(im)
    for c in draws:
        font = ImageFont.truetype(c["font"], int(round(c["size"] * SS)), layout_engine=ImageFont.Layout.RAQM)
        if c["kind"] == "plain":
            width = font.getlength(c["text"]) / SS
            x = c["x"] - (width / 2 if c["anchor"] == "middle" else width if c["anchor"] == "end" else 0)
            d.text((x * SS, c["y"] * SS), c["text"], font=font, fill=c["fill"], anchor="ls")
            continue
        pts = [(x * SS, y * SS) for x, y in c["points"]]
        lens = [0.0]
        for i in range(1, len(pts)):
            lens.append(lens[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
        total = lens[-1]
        whole = font.getlength(c["text"])
        begin = c["begin"] * SS
        if c["anchor"] == "middle": begin -= whole / 2
        elif c["anchor"] == "end": begin -= whole
        g = int(round(c["size"] * SS * 3))
        for i, ch in enumerate(c["text"]):
            before = font.getlength(c["text"][:i])
            after = font.getlength(c["text"][:i + 1])
            adv = after - before
            centre = begin + before + adv / 2
            if ch == " " or not 0 <= centre <= total: continue
            k = 1
            while k + 1 < len(pts) and lens[k] < centre: k += 1
            span = lens[k] - lens[k - 1]
            t = (centre - lens[k - 1]) / span if span > 0 else 0.0
            px = pts[k - 1][0] + (pts[k][0] - pts[k - 1][0]) * t
            py = pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * t
            angle = math.atan2(pts[k][1] - pts[k - 1][1], pts[k][0] - pts[k - 1][0])
            layer = Image.new("L", (g, g), 0)
            ImageDraw.Draw(layer).text((g / 2 - adv / 2, g / 2), ch, font=font, fill=255, anchor="ls")
            layer = layer.rotate(-math.degrees(angle), resample=Image.BICUBIC, center=(g / 2, g / 2))
            colour = Image.new("RGB", (g, g), c["fill"])
            im.paste(colour, (int(round(px - g / 2)), int(round(py - g / 2))), layer)
    small = im.resize((W, H), Image.BOX)
    out = bytearray()
    px = small.load()
    for cy in range(CH):
        for cx in range(CW):
            sums = [0, 0, 0]
            for y in range(4):
                for x in range(4):
                    p = px[cx * 4 + x, cy * 4 + y]
                    for k in range(3):
                        sums[k] += p[k]
            out.extend(s // 16 for s in sums)
    return bytes(out)


def neper_string(data):
    return "".join("\\x%02x" % b for b in data)


def neper_text(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    lines = []
    for index, (label, svg, draws) in enumerate(CASES):
        lines.append("    // %d: %s." % (index + 1, label))
        lines.append('    if !matches(a, device, faces[0usize..4usize], "%s", "%s") { os.exit(%di32) }' % (neper_text(svg), neper_string(reference(draws)), index + 1))
    path = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "gfx_svg_text_faces", "src", "main.e")
    with open(path, encoding="utf-8") as f:
        src = f.read()
    a = src.index("    // BEGIN CASES")
    b = src.index("    // END CASES")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(src[:a] + "    // BEGIN CASES (scripts/gen_svg_text_faces_test.py)\n" + "\n".join(lines) + "\n" + src[b:])
    print("%d cases written" % len(CASES))


if __name__ == "__main__":
    main()
