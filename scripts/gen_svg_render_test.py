"""Writes tests/selfhost/fixtures/link/gfx_svg_render (L125, D2843).

Each case is an SVG document drawn by cairosvg at 64 x 64 on white and box-reduced to
16 x 16 RGB (4 x 4 cells); the fixture renders the same document through
`e.gfx.svg` -> `e.gfx.scene` -> the CPU backend, reduces it the same way and holds the
mean and the largest cell difference to a tolerance. The documents use what the
renderer now draws beyond shapes: linear and radial gradients (bounding-box and
user-space units, stop opacity, href-inherited stops, gradientTransform), `defs` and
`use`, units and percentages, and a clip path; plus two plain-shape documents so the
older renderer is measured against the same reference. D3100 adds style sheets,
preserveAspectRatio, spread, dashes, even-odd, patterns and markers.

    python scripts/gen_svg_render_test.py
"""
import io
import os
import sys

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIDE = 64
CELLS = 16

CASES = [
    ("linear gradient, bounding box",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs><rect x="10" y="10" width="80" height="80" fill="url(#g)"/></svg>'),
    ("linear gradient, user space, three stops, stop opacity",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="100"><stop offset="0" stop-color="#00aa00"/><stop offset="0.5" stop-color="#ffff00" stop-opacity="0.5"/><stop offset="1" stop-color="#8000ff"/></linearGradient></defs><rect width="100" height="100" fill="url(#g)"/></svg>'),
    ("radial gradient on a circle",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="r" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#0000c0"/></radialGradient></defs><circle cx="50" cy="50" r="40" fill="url(#r)"/></svg>'),
    ("gradient stroke and href stops",
     '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100"><defs><linearGradient id="base"><stop offset="0" stop-color="#ff8000"/><stop offset="1" stop-color="#0080ff"/></linearGradient><linearGradient id="g" xlink:href="#base" x1="0" y1="0" x2="0" y2="1"/></defs><rect x="20" y="20" width="60" height="60" fill="none" stroke="url(#g)" stroke-width="12"/></svg>'),
    ("gradientTransform",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" gradientTransform="rotate(90 0.5 0.5)"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#ffff00"/></linearGradient></defs><rect x="10" y="10" width="80" height="80" fill="url(#g)"/></svg>'),
    ("defs and use",
     '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100"><defs><g id="tile"><rect width="20" height="20"/><circle cx="10" cy="10" r="4" fill="#ffffff"/></g></defs><use xlink:href="#tile" x="10" y="10" fill="#ff0000"/><use href="#tile" x="40" y="40" fill="#0000ff"/><use href="#tile" x="70" y="10" fill="#008000"/></svg>'),
    ("units and percentages",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect x="10%" y="10" width="50%" height="30" fill="#800080"/><rect x="1in" y="2cm" width="20mm" height="15pt" fill="#ff8000"/></svg>'),
    ("clip path",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><clipPath id="c"><rect x="25" y="25" width="50" height="50"/></clipPath></defs><circle cx="50" cy="50" r="45" fill="#ff0000" clip-path="url(#c)"/></svg>'),
    ("plain shapes and strokes",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="8" y="8" width="40" height="30" rx="6" fill="#336699"/><circle cx="70" cy="30" r="18" fill="none" stroke="#cc3300" stroke-width="5"/><polygon points="20,90 50,50 80,90" fill="#009966"/><path d="M10 60 Q 30 40 50 60 T 90 60" fill="none" stroke="#000000" stroke-width="3" stroke-linecap="round"/></svg>'),
    ("style sheet: type, class and id rules over attributes",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><style>rect{stroke:#000000;stroke-width:4}.a{fill:#ff0000}#b{fill:#00a000}</style><rect class="a" x="10" y="10" width="35" height="35" fill="#0000ff"/><rect id="b" class="a" x="55" y="10" width="35" height="35"/><rect x="10" y="55" width="35" height="35" fill="#ffff00" style="fill:#800080"/></svg>'),
    ("preserveAspectRatio slice, xMinYMax",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50" preserveAspectRatio="xMinYMax slice"><rect width="100" height="50" fill="#fff0c0"/><circle cx="25" cy="25" r="20" fill="#d03030"/><rect x="60" y="5" width="30" height="40" fill="#3050d0"/></svg>'),
    ("preserveAspectRatio none",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50" preserveAspectRatio="none"><circle cx="50" cy="25" r="22" fill="#209040"/></svg>'),
    ("linear gradient, spread reflect",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" x1="0.4" y1="0" x2="0.6" y2="0" spreadMethod="reflect"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs><rect x="5" y="5" width="90" height="90" fill="url(#g)"/></svg>'),
    ("linear gradient, spread repeat, diagonal",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="20" y1="20" x2="45" y2="45" spreadMethod="repeat"><stop offset="0" stop-color="#ffcc00"/><stop offset="1" stop-color="#006600"/></linearGradient></defs><rect x="5" y="5" width="90" height="90" fill="url(#g)"/></svg>'),
    ("radial gradient, spread reflect",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="r" cx="0.5" cy="0.5" r="0.2" spreadMethod="reflect"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#800000"/></radialGradient></defs><rect x="5" y="5" width="90" height="90" fill="url(#r)"/></svg>'),
    ("stroke-dasharray with offset",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M10 20 H90 M10 50 H90 M10 80 H90" fill="none" stroke="#000000" stroke-width="8" stroke-dasharray="14 6" stroke-dashoffset="5"/></svg>'),
    ("dashes round caps on a circle",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="38" fill="none" stroke="#c02020" stroke-width="7" stroke-linecap="round" stroke-dasharray="1 16"/></svg>'),
    ("fill-rule evenodd, nested loops",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill-rule="evenodd" fill="#2060a0" d="M5 5H95V95H5Z M20 20H80V80H20Z M35 35H65V65H35Z"/></svg>'),
    ("fill-rule evenodd, circles and a nonzero twin",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill-rule="evenodd" fill="#b04080" d="M50 5A45 45 0 1 1 49.9 5Z M50 20A30 30 0 1 1 49.9 20Z"/></svg>'),
    ("pattern tiles",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><pattern id="p" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse"><rect width="10" height="10" fill="#d02020"/><rect x="10" y="10" width="10" height="10" fill="#2020d0"/></pattern></defs><circle cx="50" cy="50" r="42" fill="url(#p)"/></svg>'),
    ("markers on a polyline",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><marker id="m" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto"><circle cx="3" cy="3" r="3" fill="#d02020"/></marker></defs><polyline points="15,80 40,25 65,70 90,20" fill="none" stroke="#000000" stroke-width="3" marker-start="url(#m)" marker-mid="url(#m)" marker-end="url(#m)"/></svg>'),
    ("icon-like path with arcs",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 2 a10 10 0 1 0 0.01 0 z M12 6 v6 l4 2" fill="none" stroke="#222222" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
]

# D3701: group opacity as a layer, selector combinators, pattern viewBox and href, a radial focal point.
H = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100">'
CASES += [
    ("group opacity composites the group once",
     H + '<g opacity="0.5"><rect x="10" y="10" width="50" height="50" fill="#ff0000"/><rect x="40" y="40" width="50" height="50" fill="#0000ff"/></g></svg>'),
    ("nested group opacities",
     H + '<g opacity="0.5"><g opacity="0.5"><rect x="10" y="10" width="45" height="45" fill="#00a000"/><rect x="35" y="35" width="45" height="45" fill="#800080"/></g><rect x="60" y="5" width="35" height="30" fill="#000000"/></g></svg>'),
    ("selector: child combinator over a type rule",
     H + '<style>g > rect{fill:#ff0000}rect{fill:#0000ff}</style><g><rect x="10" y="10" width="30" height="30"/></g><rect x="60" y="60" width="30" height="30"/></svg>'),
    ("selector: descendant combinator through two groups",
     H + '<style>g rect{fill:#00a000}rect{fill:#0000ff}</style><g><g><rect x="10" y="10" width="30" height="30"/></g></g><rect x="60" y="60" width="30" height="30"/></svg>'),
    ("selector: adjacent sibling and first-child",
     H + '<style>rect + circle{fill:#ff00ff}circle{fill:#000000}g > rect:first-child{stroke:#ff8000;stroke-width:6}</style><g><rect x="8" y="8" width="30" height="30" fill="#cccccc"/><circle cx="62" cy="24" r="14"/><circle cx="62" cy="74" r="14"/></g></svg>'),
    ("selector: attribute match and a class that outranks a combinator",
     H + '<style>rect[data-k=a]{fill:#ff8000}.k{fill:#008080}g rect{fill:#c00000}</style><g><rect data-k="a" x="5" y="5" width="30" height="30"/><rect class="k" x="50" y="5" width="30" height="30"/><rect x="5" y="50" width="30" height="30" fill="#0000ff"/></g></svg>'),
    ("pattern with a viewBox",
     H + '<defs><pattern id="p" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse" viewBox="0 0 10 10"><rect width="5" height="5" fill="#d02020"/><rect x="5" y="5" width="5" height="5" fill="#2020d0"/></pattern></defs><rect width="100" height="100" fill="url(#p)"/></svg>'),
    ("pattern inheriting content and size by href",
     H + '<defs><pattern id="base" width="20" height="20" patternUnits="userSpaceOnUse"><circle cx="10" cy="10" r="6" fill="#208020"/></pattern><pattern id="p" xlink:href="#base" x="5" y="5"/></defs><rect width="100" height="100" fill="url(#p)"/></svg>'),
    ("radial gradient with a focal point",
     H + '<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5" fx="0.3" fy="0.3"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#0000ff"/></radialGradient></defs><rect width="100" height="100" fill="url(#g)"/></svg>'),
    ("radial focal point in user space, three stops",
     H + '<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="40" fx="70" fy="35"><stop offset="0" stop-color="#ffff00"/><stop offset="0.5" stop-color="#ff0000"/><stop offset="1" stop-color="#000080"/></radialGradient></defs><circle cx="50" cy="50" r="46" fill="url(#g)"/></svg>'),
]

# D3701: masks. cairosvg draws a mask by alpha alone, so the oracle is the SVG compositing formula over
# cairosvg's own rasters: the element alone, and the mask's content alone, per pixel at 64 x 64.
MASK_CASES = [
    ("use opacity composites the referenced group once (cairosvg ignores it, so: the formula)",
     H + '<defs><g id="two"><circle cx="35" cy="40" r="25" fill="#ff8000"/><circle cx="60" cy="55" r="25" fill="#0080ff"/></g></defs><use xlink:href="#two" opacity="0.6"/></svg>',
     H + '<defs><g id="two"><circle cx="35" cy="40" r="25" fill="#ff8000"/><circle cx="60" cy="55" r="25" fill="#0080ff"/></g></defs><use xlink:href="#two"/></svg>',
     H + '<rect width="100" height="100" fill="#ffffff" fill-opacity="0.6"/></svg>'),
    ("element opacity composites fill and stroke once (cairosvg multiplies them apart, so: the formula)",
     H + '<rect x="20" y="20" width="60" height="60" fill="#ff0000" stroke="#0000ff" stroke-width="20" opacity="0.5"/></svg>',
     H + '<rect x="20" y="20" width="60" height="60" fill="#ff0000" stroke="#0000ff" stroke-width="20"/></svg>',
     H + '<rect width="100" height="100" fill="#ffffff" fill-opacity="0.5"/></svg>'),
    ("mask: a mid-grey rectangle halves the element",
     H + '<defs><mask id="m"><rect x="0" y="0" width="100" height="100" fill="#808080"/></mask></defs><rect x="10" y="10" width="80" height="80" fill="#0000ff" mask="url(#m)"/></svg>',
     H + '<rect x="10" y="10" width="80" height="80" fill="#0000ff"/></svg>',
     H + '<rect x="0" y="0" width="100" height="100" fill="#808080"/></svg>'),
    ("mask: a black to white gradient fades the element",
     H + '<defs><linearGradient id="g"><stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/></linearGradient><mask id="m"><rect x="0" y="0" width="100" height="100" fill="url(#g)"/></mask></defs><rect x="5" y="5" width="90" height="90" fill="#cc0000" mask="url(#m)"/></svg>',
     H + '<rect x="5" y="5" width="90" height="90" fill="#cc0000"/></svg>',
     H + '<defs><linearGradient id="g"><stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/></linearGradient></defs><rect x="0" y="0" width="100" height="100" fill="url(#g)"/></svg>'),
    ("mask: two disjoint shapes, white and half-opaque white, over a group",
     H + '<defs><mask id="m"><circle cx="30" cy="50" r="22" fill="#ffffff"/><rect x="55" y="25" width="40" height="50" fill="#ffffff" fill-opacity="0.4"/></mask></defs><g mask="url(#m)"><rect x="0" y="0" width="100" height="60" fill="#008000"/><rect x="0" y="40" width="100" height="60" fill="#800080"/></g></svg>',
     H + '<g><rect x="0" y="0" width="100" height="60" fill="#008000"/><rect x="0" y="40" width="100" height="60" fill="#800080"/></g></svg>',
     H + '<circle cx="30" cy="50" r="22" fill="#ffffff"/><rect x="55" y="25" width="40" height="50" fill="#ffffff" fill-opacity="0.4"/></svg>'),
    ("mask: a transformed element keeps the mask in its own space",
     H + '<defs><mask id="m"><rect x="0" y="0" width="30" height="60" fill="#ffffff"/></mask></defs><rect x="0" y="0" width="60" height="60" fill="#ff8000" transform="translate(30 20)" mask="url(#m)"/></svg>',
     H + '<rect x="0" y="0" width="60" height="60" fill="#ff8000" transform="translate(30 20)"/></svg>',
     H + '<rect x="0" y="0" width="30" height="60" fill="#ffffff" transform="translate(30 20)"/></svg>'),
    # D4504: the mask's region and content units. The element is the content (clipped to the region by
    # a clip path cairosvg draws); the mask is the mask's own content in the element's user space.
    ("mask region, userSpaceOnUse: only the part inside the rectangle shows",
     H + '<defs><mask id="m" maskUnits="userSpaceOnUse" x="20" y="20" width="60" height="60"><rect x="0" y="0" width="100" height="100" fill="#ffffff"/></mask></defs><rect x="10" y="10" width="80" height="80" fill="#0000ff" mask="url(#m)"/></svg>',
     H + '<defs><clipPath id="c"><rect x="20" y="20" width="60" height="60"/></clipPath></defs><rect x="10" y="10" width="80" height="80" fill="#0000ff" clip-path="url(#c)"/></svg>',
     H + '<rect x="0" y="0" width="100" height="100" fill="#ffffff"/></svg>'),
    ("mask region in box fractions: the left half of the element's box",
     H + '<defs><mask id="m" x="0" y="0" width="0.5" height="1"><rect x="0" y="0" width="100" height="100" fill="#ffffff"/></mask></defs><rect x="10" y="10" width="80" height="80" fill="#c04000" mask="url(#m)"/></svg>',
     H + '<defs><clipPath id="c"><rect x="10" y="10" width="40" height="80"/></clipPath></defs><rect x="10" y="10" width="80" height="80" fill="#c04000" clip-path="url(#c)"/></svg>',
     H + '<rect x="0" y="0" width="100" height="100" fill="#ffffff"/></svg>'),
    ("maskContentUnits objectBoundingBox: the content's rectangle is in box fractions",
     H + '<defs><mask id="m" maskContentUnits="objectBoundingBox"><rect x="0" y="0" width="0.5" height="1" fill="#ffffff"/></mask></defs><rect x="20" y="20" width="60" height="60" fill="#00a000" mask="url(#m)"/></svg>',
     H + '<rect x="20" y="20" width="60" height="60" fill="#00a000"/></svg>',
     H + '<rect x="20" y="20" width="30" height="60" fill="#ffffff"/></svg>'),
    ("maskContentUnits objectBoundingBox with a gradient across the box",
     H + '<defs><linearGradient id="g"><stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/></linearGradient><mask id="m" maskContentUnits="objectBoundingBox"><rect x="0" y="0" width="1" height="1" fill="url(#g)"/></mask></defs><rect x="15" y="25" width="70" height="50" fill="#a000a0" mask="url(#m)"/></svg>',
     H + '<rect x="15" y="25" width="70" height="50" fill="#a000a0"/></svg>',
     H + '<defs><linearGradient id="g"><stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/></linearGradient></defs><rect x="15" y="25" width="70" height="50" fill="url(#g)"/></svg>'),
    ("mask region and content units together on a translated element",
     H + '<defs><mask id="m" x="0.25" y="0" width="0.5" height="1" maskContentUnits="objectBoundingBox"><rect x="0" y="0" width="1" height="1" fill="#ffffff"/></mask></defs><rect x="0" y="0" width="50" height="60" fill="#e08000" transform="translate(30 20)" mask="url(#m)"/></svg>',
     H + '<defs><clipPath id="c"><rect x="12.5" y="0" width="25" height="60"/></clipPath></defs><rect x="0" y="0" width="50" height="60" fill="#e08000" transform="translate(30 20)" clip-path="url(#c)"/></svg>',
     H + '<rect x="0" y="0" width="100" height="100" fill="#ffffff"/></svg>'),
]


def lum(p):
    return (0.2125 * p[0] + 0.7154 * p[1] + 0.0721 * p[2]) / 255.0


def reference_mask(content, mask):
    """White background, the element composited with the mask's luminance times alpha."""
    def rgba(svg):
        png = cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=SIDE, output_height=SIDE)
        return Image.open(io.BytesIO(png)).convert("RGBA").load()
    c = rgba(content)
    m = rgba(mask)
    out = Image.new("RGB", (SIDE, SIDE))
    po = out.load()
    for y in range(SIDE):
        for x in range(SIDE):
            r, g, b, a = c[x, y]
            mr, mg, mb, ma = m[x, y]
            k = lum((mr, mg, mb)) * (ma / 255.0) * (a / 255.0)
            po[x, y] = tuple(int(round(255 * (1 - k) + ch * k)) for ch in (r, g, b))
    return out


def reduce_image(im):
    cell = SIDE // CELLS
    out = bytearray()
    px = im.load()
    for cy in range(CELLS):
        for cx in range(CELLS):
            sums = [0, 0, 0]
            for y in range(cell):
                for x in range(cell):
                    p = px[cx * cell + x, cy * cell + y]
                    for k in range(3):
                        sums[k] += p[k]
            out.extend(s // (cell * cell) for s in sums)
    return bytes(out)


def reference(svg):
    png = cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=SIDE, output_height=SIDE, background_color="white")
    im = Image.open(io.BytesIO(png)).convert("RGB")
    cell = SIDE // CELLS
    out = bytearray()
    px = im.load()
    for cy in range(CELLS):
        for cx in range(CELLS):
            sums = [0, 0, 0]
            for y in range(cell):
                for x in range(cell):
                    p = px[cx * cell + x, cy * cell + y]
                    for k in range(3):
                        sums[k] += p[k]
            out.extend(s // (cell * cell) for s in sums)
    return bytes(out)


def neper_string(data):
    return "".join("\\x%02x" % b for b in data)


def neper_text(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    lines = []
    for index, (label, svg) in enumerate(CASES):
        ref = reference(svg)
        lines.append("    // %d: %s." % (index + 1, label))
        lines.append('    if !matches(a, device, "%s", "%s", %di32) { os.exit(%di32) }' % (neper_text(svg), neper_string(ref), index + 1, index + 1))
    for k, (label, svg, content, mask) in enumerate(MASK_CASES):
        index = len(CASES) + k
        ref = reduce_image(reference_mask(content, mask))
        lines.append("    // %d: %s." % (index + 1, label))
        lines.append('    if !matches(a, device, "%s", "%s", %di32) { os.exit(%di32) }' % (neper_text(svg), neper_string(ref), index + 1, index + 1))
    body = "\n".join(lines)
    source = TEMPLATE.replace("@@CASES@@", body)
    path = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "gfx_svg_render", "src", "main.e")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(source)
    print("wrote %d cases -> %s" % (len(CASES), path))


TEMPLATE = r'''// `e.gfx.svg` against cairosvg (L125): each document is drawn at 64 x 64 on white
// through `e.gfx.scene` and the CPU backend, reduced to 16 x 16 RGB in 4 x 4 cells and
// compared with cairosvg's reduction (scripts/gen_svg_render_test.py wrote the
// vectors). The mean absolute channel difference must stay under 3 of 255 and no cell
// may differ by more than 56 on any channel (anti-aliasing of edges lives there).
// Gradients (box and user space, three stops, stop opacity, href stops,
// gradientTransform, on stroke), defs and use, units and percentages and a clip path
// are checked, with plain shapes and a stroked icon path for the older renderer.
// Each check exits with its own code.

use e.gfx.svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.mem
use e.os

const SIDE: usize = 64usize
const CELLS: usize = 16usize
const CELL: i32 = 56i32

fn mean_limit() -> f32 { ret 3.0 }

fn render(a: *mem.Arena, device: *gpu.Device, text: str) -> ([]u32, err) {
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, queue_error) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { ret (zero, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (zero, canvas_error) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret (zero, renderer_error) }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 2048usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 64.0, 64.0), brush: paint.Brush { Solid: paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } } } })
    try svg.draw(a, &builder, text, geometry.rect(0.0, 0.0, 64.0, 64.0), paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret (zero, compile_error) }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: 64.0, height: 64.0 })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (zero, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(q, image, pixels) != ok { ret (zero, gpu.OutOfMemory) }
    ret (pixels, ok)
}

// The 4 x 4 cell mean of channel `shift` (16 red, 8 green, 0 blue) at cell (cx, cy).
fn cell_mean(pixels: []const u32, cx: usize, cy: usize, shift: u32) -> i32 {
    var sum = 0u32
    var y = 0usize
    while y < 4usize {
        var x = 0usize
        while x < 4usize {
            sum += (pixels[(cy * 4usize + y) * SIDE + cx * 4usize + x] >> shift) & 255u32
            x += 1usize
        }
        y += 1usize
    }
    ret i32(sum / 16u32)
}

// Does `text` draw to within tolerance of the reference cells? `code` is for the exit.
fn matches(a: *mem.Arena, device: *gpu.Device, text: str, want: str, code: i32) -> bool {
    let mark = mem.mark(a)
    let (pixels, pixels_error) = render(a, device, text)
    if pixels_error != ok { ret false }
    var total = 0i64
    var worst = 0i32
    var cy = 0usize
    while cy < CELLS {
        var cx = 0usize
        while cx < CELLS {
            var channel = 0usize
            while channel < 3usize {
                var shift = 16u32
                if channel == 1usize { shift = 8u32 }
                if channel == 2usize { shift = 0u32 }
                let got = cell_mean(pixels, cx, cy, shift)
                var diff = got - i32(want[(cy * CELLS + cx) * 3usize + channel])
                if diff < 0i32 { diff = 0i32 - diff }
                total += i64(diff)
                if diff > worst { worst = diff }
                channel += 1usize
            }
            cx += 1usize
        }
        cy += 1usize
    }
    mem.reset(a, mark)
    let mean_diff = f32(total) / f32(CELLS * CELLS * 3usize)
    ret mean_diff <= mean_limit() && worst <= CELL
}

fn main(a: *mem.Arena, args: []str) -> err {
    // One device for every document: a process opens at most sixteen.
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { os.exit(80i32) }
@@CASES@@
    // A gradient naming nothing draws nothing, and an unknown use is skipped: the
    // document is still valid.
    let (blank, blank_error) = render(a, device, "<svg viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"url(#missing)\"/><use href=\"#nothing\"/></svg>")
    if blank_error != ok { os.exit(90i32) }
    if blank[32usize * SIDE + 32usize] != 4294967295u32 { os.exit(91i32) }
    // A use cycle is refused rather than recursed into.
    let (_, cycle_error) = render(a, device, "<svg viewBox=\"0 0 10 10\"><defs><g id=\"g\"><use href=\"#g\"/></g></defs><use href=\"#g\"/></svg>")
    if cycle_error != svg.TooComplex { os.exit(92i32) }
    ret ok
}
'''

if __name__ == "__main__":
    main()
