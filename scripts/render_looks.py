"""Render docs/ui/looks-progress.html from docs/ui/looks/status.json.

One self-contained page (inline CSS and JS, no external assets; thumbnails are the repository's own
PNGs under docs/ui/looks/): a controls x looks matrix of status chips and thumbnails, a status
filter, counts per look, and the gap list. Never hand-edited. `python scripts/render_looks.py`.
"""
import json
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "docs/ui/looks/status.json"
OUT = ROOT / "docs/ui/looks-progress.html"
ORDER = ["planned", "started", "review", "ready"]

CSS = """
:root{--bg:#f6f7f9;--fg:#1c1e22;--mut:#5d6470;--card:#fff;--line:#d9dde3;--planned:#8a909b;--started:#b36b00;--review:#1a62b8;--ready:#1f7a3d;--chip:#eef0f3}
@media(prefers-color-scheme:dark){:root{--bg:#14161a;--fg:#e6e8ec;--mut:#9aa1ad;--card:#1c1f25;--line:#323741;--planned:#8f96a3;--started:#e0a040;--review:#6aa7f0;--ready:#5dc07c;--chip:#272b33}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,"Segoe UI",sans-serif}
main{max-width:1200px;margin:0 auto;padding:16px}h1{font-size:1.4rem;margin:.2em 0}h2{font-size:1.1rem;margin:1.6em 0 .5em}
.mut{color:var(--mut)}.sum{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:10px}
.box{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px}
.box b{display:block;margin-bottom:4px}.bar{display:flex;height:8px;border-radius:4px;overflow:hidden;background:var(--chip);margin:6px 0}
.bar i{display:block;height:100%}.counts{display:flex;gap:8px;flex-wrap:wrap;font-size:.85rem}
.chip{display:inline-block;border-radius:10px;padding:0 8px;font-size:.78rem;font-weight:600;color:#fff;line-height:1.5}
.s-planned{background:var(--planned)}.s-started{background:var(--started)}.s-review{background:var(--review)}.s-ready{background:var(--ready)}
.filter{display:flex;gap:6px;flex-wrap:wrap;margin:14px 0}.filter button{border:1px solid var(--line);background:var(--card);color:var(--fg);border-radius:16px;padding:4px 12px;font:inherit;cursor:pointer}
.filter button[aria-pressed=true]{background:var(--fg);color:var(--bg)}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:8px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}th{font-size:.8rem;color:var(--mut)}
td.name b{display:block}td.name span{font-size:.8rem;color:var(--mut)}
.cell a.thumb{display:block;margin-top:4px}.cell img{max-width:100%;max-height:70px;border:1px solid var(--line);border-radius:4px;background:#fff}
.cell .note{font-size:.78rem;color:var(--mut);margin-top:3px}.cell.dim{opacity:.35}
details{font-size:.78rem;margin-top:3px}summary{cursor:pointer;color:var(--mut)}details ul{margin:.3em 0 0 1.1em;padding:0}
tr.hide{display:none}ul.gaps{padding-left:1.1em}
@media(max-width:760px){table,thead,tbody,tr,td{display:block}thead{display:none}tr{margin:10px 0;border:1px solid var(--line);border-radius:8px;padding:6px}
td{border:0;padding:6px 8px}td.cell::before{content:attr(data-look);display:block;font-size:.75rem;color:var(--mut)}}
"""

JS = """
const rows=[...document.querySelectorAll('tbody tr')];
function apply(s){document.querySelectorAll('.filter button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.s===s));
rows.forEach(r=>{const cells=[...r.querySelectorAll('.cell')];const hit=s==='all'||cells.some(c=>c.dataset.status===s);
r.classList.toggle('hide',!hit);cells.forEach(c=>c.classList.toggle('dim',s!=='all'&&c.dataset.status!==s))})}
document.querySelectorAll('.filter button').forEach(b=>b.addEventListener('click',()=>apply(b.dataset.s)));
"""


def cell(control, look, shots):
    info = (control.get("looks") or {}).get(look["id"], {})
    status = info.get("status", "planned")
    out = ['<td class="cell" data-look="%s" data-status="%s">' % (escape(look["label"]), status)]
    out.append('<span class="chip s-%s">%s</span>' % (status, status))
    shot = info.get("screenshot") or ""
    if shot and (shots / shot).exists():
        href = "looks/" + shot
        out.append('<a class="thumb" href="%s"><img loading="lazy" alt="%s %s" src="%s"></a>'
                   % (escape(href), escape(look["label"]), escape(control["name"]), escape(href)))
    elif shot:
        out.append('<div class="note">screenshot missing: %s</div>' % escape(shot))
    if info.get("notes"):
        out.append('<div class="note">%s</div>' % escape(info["notes"]))
    gaps = info.get("gaps") or []
    if gaps:
        out.append("<details><summary>%d known gap%s</summary><ul>%s</ul></details>"
                   % (len(gaps), "" if len(gaps) == 1 else "s", "".join("<li>%s</li>" % escape(g) for g in gaps)))
    out.append("</td>")
    return "".join(out)


def main():
    data = json.loads(STATUS.read_text(encoding="utf-8"))
    looks, controls = data["looks"], data["controls"]
    shots = ROOT / "docs/ui/looks"
    counts = {l["id"]: {s: 0 for s in ORDER} for l in looks}
    for c in controls:
        for l in looks:
            st = (c.get("looks") or {}).get(l["id"], {}).get("status", "planned")
            if st not in ORDER:
                raise SystemExit("%s/%s: unknown status %r" % (c["id"], l["id"], st))
            counts[l["id"]][st] += 1
    p = []
    p.append('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    p.append("<title>Neper looks progress</title><style>%s</style></head><body><main>" % CSS)
    p.append("<h1>Neper looks progress</h1>")
    p.append('<p class="mut">One widget set, several platform looks (docs/ui/looks-plan.md). Generated from '
             'docs/ui/looks/status.json by scripts/render_looks.py; updated %s. %d controls.</p>'
             % (escape(data.get("updated", "")), len(controls)))
    p.append('<div class="sum">')
    total = len(controls)
    for l in looks:
        c = counts[l["id"]]
        bar = "".join('<i class="s-%s" style="width:%.1f%%"></i>' % (s, 100.0 * c[s] / total) for s in reversed(ORDER))
        chips = "".join('<span><span class="chip s-%s">%s</span> %d</span>' % (s, s, c[s]) for s in ORDER)
        p.append('<div class="box"><b>%s</b><div class="mut">profile %s</div><div class="bar">%s</div><div class="counts">%s</div></div>'
                 % (escape(l["label"]), escape(l["profile"]), bar, chips))
    p.append("</div>")
    p.append('<div class="filter" role="group" aria-label="Filter by status"><button data-s="all" aria-pressed="true">all</button>%s</div>'
             % "".join('<button data-s="%s" aria-pressed="false">%s</button>' % (s, s) for s in ORDER))
    p.append("<table><thead><tr><th>Control</th>%s</tr></thead><tbody>" % "".join("<th>%s</th>" % escape(l["label"]) for l in looks))
    for c in controls:
        neper = c.get("neper")
        sub = "%s &rarr; %s" % (escape(c.get("delphi", "")), escape(neper) if neper else "<i>no Neper control</i>")
        p.append('<tr><td class="name"><b>%s</b><span>%s</span></td>' % (escape(c["name"]), sub))
        for l in looks:
            p.append(cell(c, l, shots))
        p.append("</tr>")
    p.append("</tbody></table>")
    p.append("<h2>Gaps: no Neper equivalent yet</h2><ul class=\"gaps\">")
    seen = set()
    for g in data.get("gaps", []):
        seen.add(g["item"])
        p.append("<li><b>%s</b> (%s): %s</li>" % (escape(g["item"]), escape(g.get("delphi", "")), escape(g.get("note", ""))))
    for c in controls:
        if c.get("gap") and c["name"] not in seen and not any(c["name"].lower() in s.lower() for s in seen):
            p.append("<li><b>%s</b> (%s): %s</li>" % (escape(c["name"]), escape(c.get("delphi", "")), escape(c["gap"])))
    p.append("</ul><script>%s</script></main></body></html>" % JS)
    OUT.write_text("".join(p), encoding="utf-8")
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
