import re
from pathlib import Path
import sys
base=Path(sys.argv[1])  # a folder holding the Adwaita symbolic SVGs copied flat (WSL: /usr/share/icons/Adwaita/symbolic/*/NAME.svg)
icons=[("edit_clear","actions/edit-clear-symbolic"),("edit_find","actions/edit-find-symbolic"),("view_reveal","actions/view-reveal-symbolic"),
("view_conceal","actions/view-conceal-symbolic"),("pan_down","ui/pan-down-symbolic"),("pan_start","ui/pan-start-symbolic"),("pan_end","ui/pan-end-symbolic"),
("list_add","actions/list-add-symbolic"),("list_remove","actions/list-remove-symbolic"),("object_select","actions/object-select-symbolic"),("value_increase","actions/value-increase-symbolic"),("value_decrease","actions/value-decrease-symbolic")]
out=['// Adwaita symbolic icons (adwaita-icon-theme, 16 x 16 viewBox, CC-BY-SA 3.0 / LGPL-3), each as an SVG document whose path fills',
'// `currentColor`: the Linux look draws them with e.ui.gridlook.svg_mark in the colour of the text beside them.','',
'use e.mem','use e.gfx.paint','use e.ui.gridlook as gl','use e.ui.widget','']
for name,rel in icons:
    t=(base/(rel.split("/")[1]+".svg")).read_text()
    d=re.search(r' d="([^"]*)"',t).group(1)
    out.append('fn %s() -> str { ret "<svg viewBox=\\"0 0 16 16\\" xmlns=\\"http://www.w3.org/2000/svg\\"><path d=\\"%s\\" fill=\\"currentColor\\"/></svg>" }'%(name,d))
    out.append('')
out.append('// The icon `name` (a function above, as text) as a `size` px square in `color`.')
out.append('fn icon(a: *mem.Arena, svg: str, color: paint.Color, size: f32) -> (widget.Node, err) {')
out.append('    let (node, node_error) = gl.svg_mark(a, svg, color, size, size)'); out.append('    ret (node, node_error)')
out.append('}')
(Path(__file__).resolve().parents[2] / 'lib/e/ui/adwicon_l2.e').write_text('\n'.join(out)+'\n',encoding='utf-8')
print(len('\n'.join(out)))
