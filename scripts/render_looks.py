"""Render docs/ui/looks-progress.html from docs/ui/looks/status.json (+ status.d overlays).

One self-contained page (inline CSS and JS, no external assets; thumbnails are the repository's own
PNGs under docs/ui/looks/, inlined as 150 px high base64 so the page opens from file:// with no
network): eight looks (status.json "looks": neper, neper_dark, windows, windows_dark, cupertino,
cupertino_dark, material, material_dark) shown as four flavor columns, each cell holding the Light and
the Dark thumbnail side by side with its own status chip, notes and gaps; one summary box per look, a
status filter and the gap list. Never hand-edited. `python scripts/render_looks.py`.

Overlays (docs/ui/looks/status.d/*.json): {"<control id>": {"looks": {"<look id>": {...}}}}; an entry
replaces the base entry of that look wholesale. An id that is not in status.json controls is added as an
extra row ("Platform idiom controls", delphi column "(none)") only when its entry carries a "name".

Auto entry: a control with no entry for a look, whose picture docs/ui/looks/<look dir>/<name>.png exists
(look dir = look id with hyphens, name = control id, then the control's `app` sheet name, then its
`sheet`), is shown as `started` (rendered from the platform palette, not compared with a real screen).
An overlay or base entry always wins.
"""
import base64
import hashlib
import io
import json
import tempfile
from html import escape
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # without PIL the page falls back to the relative link
    Image = None

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "docs/ui/looks/status.json"
OUT = ROOT / "docs/ui/looks-progress.html"
SHOTS = ROOT / "docs/ui/looks"
CACHE = Path(tempfile.gettempdir()) / "neper-looks-thumbs"
# review = renders, with unmeasured or mismatching states; matched = every state that has a v3 capture
# reproduces it within tolerance (hover, pressed and other uncaptured states are listed as unverified);
# ready = matched and no unverified state is left.
ORDER = ["planned", "started", "review", "matched", "ready"]
NOTE_AUTO = "Rendered from the platform palette; not compared with a real screen."
# The four flavor columns: (heading, light look id, dark look id, what it stands for).
FLAVORS = [("Neper", "neper", "neper_dark", "the app's own look"),
           ("Windows", "windows", "windows_dark", "Windows 11; Light is audited against v3 captures"),
           ("macOS / iOS", "cupertino", "cupertino_dark", "Apple HIG (UIKit / AppKit)"),
           ("Android", "material", "material_dark", "Material 3")]

CSS = """
:root{--bg:#f6f7f9;--fg:#1c1e22;--mut:#5d6470;--card:#fff;--line:#d9dde3;--planned:#8a909b;--started:#b36b00;--review:#1a62b8;--matched:#0e7490;--ready:#1f7a3d;--chip:#eef0f3}
@media(prefers-color-scheme:dark){:root{--bg:#14161a;--fg:#e6e8ec;--mut:#9aa1ad;--card:#1c1f25;--line:#323741;--planned:#8f96a3;--started:#e0a040;--review:#6aa7f0;--matched:#4cc4e0;--ready:#5dc07c;--chip:#272b33}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,"Segoe UI",sans-serif}
main{max-width:1500px;margin:0 auto;padding:16px}h1{font-size:1.4rem;margin:.2em 0}h2{font-size:1.1rem;margin:1.6em 0 .5em}
.mut{color:var(--mut)}.sum{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}
.box{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px}
.box b{display:block;margin-bottom:2px}.bar{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--chip);margin:6px 0}
.bar i{display:block;height:100%}.counts{display:flex;gap:4px 8px;flex-wrap:wrap;font-size:.8rem}
.chip{display:inline-block;border-radius:10px;padding:0 8px;font-size:.78rem;font-weight:600;color:#fff;line-height:1.5}
.s-planned{background:var(--planned)}.s-started{background:var(--started)}.s-review{background:var(--review)}.s-matched{background:var(--matched)}.s-ready{background:var(--ready)}
.legend{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:14px 0 0}
.legend div{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font-size:.85rem}.legend b{display:block}
.filter{display:flex;gap:6px;flex-wrap:wrap;margin:14px 0}.filter button{border:1px solid var(--line);background:var(--card);color:var(--fg);border-radius:16px;padding:4px 12px;font:inherit;cursor:pointer}
.filter button[aria-pressed=true]{background:var(--fg);color:var(--bg)}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:8px;table-layout:fixed}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}th{font-size:.8rem;color:var(--mut)}
th.name,td.name{width:150px}td.name b{display:block}td.name span{font-size:.8rem;color:var(--mut)}
td.flavor{padding:6px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:6px}
.cell{min-width:0}.cell .cap{display:block;font-size:.7rem;color:var(--mut);text-transform:uppercase;letter-spacing:.04em}
.cell a.thumb{display:block;margin-top:4px}.cell img{max-width:100%;height:auto;max-height:150px;border:1px solid var(--line);border-radius:4px;background:#fff}
.cell .note{font-size:.76rem;color:var(--mut);margin-top:3px;overflow-wrap:anywhere}.cell.dim{opacity:.35}
details{font-size:.76rem;margin-top:3px}summary{cursor:pointer;color:var(--mut)}details ul{margin:.3em 0 0 1.1em;padding:0}
tr.hide,.hide{display:none}ul.gaps{padding-left:1.1em}
@media(max-width:760px){.legend{grid-template-columns:1fr 1fr}table,thead,tbody,tr,td{display:block}thead{display:none}
tr{margin:10px 0;border:1px solid var(--line);border-radius:8px;padding:6px}td{border:0;padding:6px 8px}
td.flavor::before{content:attr(data-flavor);display:block;font-size:.8rem;font-weight:600;color:var(--mut)}th.name,td.name{width:auto}}
"""

JS = """
const rows=[...document.querySelectorAll('tbody tr')];
function apply(s){document.querySelectorAll('.filter button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.s===s));
rows.forEach(r=>{const cells=[...r.querySelectorAll('.cell')];const hit=s==='all'||cells.some(c=>c.dataset.status===s);
r.classList.toggle('hide',!hit);cells.forEach(c=>c.classList.toggle('dim',s!=='all'&&c.dataset.status!==s))});
document.querySelectorAll('[data-section]').forEach(x=>x.classList.toggle('hide',![...x.querySelectorAll('tbody tr')].some(r=>!r.classList.contains('hide'))))}
document.querySelectorAll('.filter button').forEach(b=>b.addEventListener('click',()=>apply(b.dataset.s)));
"""


def thumb(path):
    """A 150 px high inline PNG of `path`, so the page shows its screenshots wherever it is opened (a viewer
    that does not resolve relative image paths, a copy emailed on its own); '' without PIL. Cached in a temp
    folder by path, mtime and size, so a re-render only decodes what changed."""
    if Image is None:
        return ""
    st = path.stat()
    key = hashlib.sha1(("%s|%d|%d|150q" % (path, st.st_mtime_ns, st.st_size)).encode()).hexdigest()
    hit = CACHE / (key + ".txt")
    try:
        return hit.read_text(encoding="ascii")
    except OSError:
        pass
    im = Image.open(path).convert("RGB")
    h = 150
    if im.height > h:
        im = im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)
    im = im.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)  # UI shots: a small palette keeps the page light
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    uri = "data:image/png;base64," + base64.b64encode(out.getvalue()).decode("ascii")
    try:
        CACHE.mkdir(parents=True, exist_ok=True)
        hit.write_text(uri, encoding="ascii")
    except OSError:
        pass
    return uri


def info_of(control, look_id):
    """The entry of a look: the overlay/base entry, else the auto `started` entry, else {} (planned)."""
    info = (control.get("looks") or {}).get(look_id)
    if info is not None:
        return info
    names = [control["id"]]
    if control.get("app"):
        names.append(Path(control["app"]).stem)
    if control.get("sheet"):
        names.append(control["sheet"])
    for n in names:
        rel = "%s/%s.png" % (look_id.replace("_", "-"), n)
        if (SHOTS / rel).exists():
            return {"status": "started", "screenshot": rel, "notes": NOTE_AUTO}
    return {}


def cell(control, look, caption):
    info = info_of(control, look["id"])
    status = info.get("status", "planned")
    out = ['<div class="cell" data-look="%s" data-status="%s"><span class="cap">%s</span>'
           % (escape(look["label"]), status, caption)]
    out.append('<span class="chip s-%s">%s</span>' % (status, status))
    shot = info.get("screenshot") or ""
    if shot and (SHOTS / shot).exists():
        href = "looks/" + shot
        src = thumb(SHOTS / shot) or href
        out.append('<a class="thumb" href="%s"><img alt="%s %s" src="%s"></a>'
                   % (escape(href), escape(look["label"]), escape(control["name"]), escape(src, quote=True)))
    elif shot:
        out.append('<div class="note">screenshot missing: %s</div>' % escape(shot))
    if info.get("notes"):
        out.append('<div class="note">%s</div>' % escape(info["notes"]))
    gaps = info.get("gaps") or []
    if gaps:
        out.append("<details><summary>%d known gap%s</summary><ul>%s</ul></details>"
                   % (len(gaps), "" if len(gaps) == 1 else "s", "".join("<li>%s</li>" % escape(g) for g in gaps)))
    out.append("</div>")
    return "".join(out)


def row(c, by_look):
    neper = c.get("neper")
    sub = "%s &rarr; %s" % (escape(c.get("delphi", "")), escape(neper) if neper else "<i>no Neper control</i>")
    r = ['<tr><td class="name"><b>%s</b><span>%s</span></td>' % (escape(c["name"]), sub)]
    for title, light, dark, _ in FLAVORS:
        r.append('<td class="flavor" data-flavor="%s"><div class="pair">%s%s</div></td>'
                 % (escape(title), cell(c, by_look[light], "light"), cell(c, by_look[dark], "dark")))
    r.append("</tr>")
    return "".join(r)


def head_row():
    return '<thead><tr><th class="name">Control</th>%s</tr></thead>' % "".join(
        '<th>%s <span class="mut">&middot; light | dark</span></th>' % escape(f[0]) for f in FLAVORS)


def main():
    data = json.loads(STATUS.read_text(encoding="utf-8"))
    looks, controls = data["looks"], data["controls"]
    by_look = {l["id"]: l for l in looks}
    for _, light, dark, _ in FLAVORS:
        if light not in by_look or dark not in by_look:
            raise SystemExit("status.json looks must list %s and %s" % (light, dark))
    # Overlays: each parallel worker owns one file; a look entry replaces the base entry wholesale. An id that is
    # not a status.json control becomes an extra row only when its entry has a "name".
    byid = {c["id"]: c for c in controls}
    extras = {}
    for f in sorted((SHOTS / "status.d").glob("*.json")):
        for cid, patch in json.loads(f.read_text(encoding="utf-8")).items():
            if cid in byid:
                target = byid[cid]
            else:
                if cid not in extras:
                    if "name" not in patch:
                        raise SystemExit("%s: unknown control %r (an extra row needs a \"name\")" % (f.name, cid))
                    extras[cid] = {"id": cid, "delphi": "(none)", "extra": True}
                target = extras[cid]
            for k, v in patch.items():
                if k == "looks":
                    target.setdefault("looks", {}).update(v)
                else:
                    target[k] = v
    extra_rows = sorted(extras.values(), key=lambda c: c["name"].lower())
    allrows = controls + extra_rows
    counts = {l["id"]: {s: 0 for s in ORDER} for l in looks}
    for c in allrows:
        for l in looks:
            st = info_of(c, l["id"]).get("status", "planned")
            if st not in ORDER:
                raise SystemExit("%s/%s: unknown status %r" % (c["id"], l["id"], st))
            counts[l["id"]][st] += 1
    p = []
    p.append('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    p.append("<title>Neper looks progress</title><style>%s</style></head><body><main>" % CSS)
    p.append("<h1>Neper looks progress</h1>")
    p.append('<p class="mut">One widget set, four platform flavors, each in a Light and a Dark look (docs/ui/looks-plan.md). Generated from '
             'docs/ui/looks/status.json and status.d by scripts/render_looks.py; updated %s. %d Delphi-equivalent controls and %d platform idiom controls. '
             'A look with no status entry whose picture exists is shown as started: rendered from the platform palette, not compared with a real screen.</p>'
             % (escape(data.get("updated", "")), len(controls), len(extra_rows)))
    p.append('<div class="sum">')
    total = len(allrows)
    for l in looks:
        c = counts[l["id"]]
        bar = "".join('<i class="s-%s" style="width:%.1f%%"></i>' % (s, 100.0 * c[s] / total) for s in reversed(ORDER))
        chips = "".join('<span><span class="chip s-%s">%s</span> %d</span>' % (s, s, c[s]) for s in ORDER)
        p.append('<div class="box"><b>%s</b><div class="mut">profile %s, %d controls</div><div class="bar">%s</div><div class="counts">%s</div></div>'
                 % (escape(l["label"]), escape(l["profile"]), total, bar, chips))
    p.append("</div>")
    p.append('<div class="legend" aria-label="Flavor columns">%s</div>' % "".join(
        '<div><b>%s</b>Light: %s<br>Dark: %s<br><span class="mut">%s</span></div>'
        % (escape(t), escape(by_look[a]["label"]), escape(by_look[b]["label"]), escape(w)) for t, a, b, w in FLAVORS))
    p.append('<div class="filter" role="group" aria-label="Filter by status"><button data-s="all" aria-pressed="true">all</button>%s</div>'
             % "".join('<button data-s="%s" aria-pressed="false">%s</button>' % (s, s) for s in ORDER))
    p.append("<table>%s<tbody>" % head_row())
    for c in controls:
        p.append(row(c, by_look))
    p.append("</tbody></table>")
    if extra_rows:
        p.append('<div data-section><h2>Platform idiom controls</h2><p class="mut">Controls the platform looks have and the Delphi app does not.</p>'
                 "<table>%s<tbody>" % head_row())
        for c in extra_rows:
            p.append(row(c, by_look))
        p.append("</tbody></table></div>")
    p.append('<h2>Gaps: no Neper equivalent yet</h2><ul class="gaps">')
    seen = set()
    for g in data.get("gaps", []):
        seen.add(g["item"])
        p.append("<li><b>%s</b> (%s): %s</li>" % (escape(g["item"]), escape(g.get("delphi", "")), escape(g.get("note", ""))))
    for c in controls:
        if c.get("gap") and c["name"] not in seen and not any(c["name"].lower() in s.lower() for s in seen):
            p.append("<li><b>%s</b> (%s): %s</li>" % (escape(c["name"]), escape(c.get("delphi", "")), escape(c["gap"])))
    p.append("</ul><script>%s</script></main></body></html>" % JS)
    OUT.write_text("".join(p), encoding="utf-8")
    print("wrote", OUT.relative_to(ROOT), "%.1f MB" % (OUT.stat().st_size / 1e6))


if __name__ == "__main__":
    main()
