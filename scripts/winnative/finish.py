"""Turns the gallery output (BMP + index-<theme>-<dpi>.tsv) into the committed reference set:
docs/ui/looks/ref/windows-native/{light,dark}/<control>-<state>@<scale>.png, manifest.csv and controls.json.
usage: python finish.py <gallery-out-dir> <dest-dir>"""
import csv, glob, json, os, sys
from PIL import Image, ImageChops

src, dest = sys.argv[1], sys.argv[2]

# first word(s) of a capture name -> Neper control id (control.* of docs/ui/looks/status.json) and the status.json id of the Delphi look it stands in for
NEPER = {
    'button': ('control.button', 'button'), 'checkbox': ('control.checkbox', 'checkbox'), 'radio': ('control.radio_group', 'radio'),
    'groupbox': ('control.group_box', 'group_box'), 'edit': ('control.text_field / control.text_area', 'text_edit, memo'),
    'label': ('control.text', 'label'), 'spin': ('control.spin_box', 'spin_edit'), 'combo': ('control.combo_box', 'combo_box'),
    'listbox': ('control.list_box', 'list_box'), 'checklist': ('control.multi_select_list', 'check_list_box'),
    'tab': ('control.tabs', 'page_control'), 'progress': ('control.progress_bar', 'progress_bar'), 'trackbar': ('(no Neper control yet)', ''),
    'vscroll': ('widget.scrollbar', 'scroll_bar'), 'hscroll': ('widget.scrollbar', 'scroll_bar'), 'statusbar': ('navigation.status_bar', 'status_bar'),
    'toolbar': ('control.glyph_button', 'toolbar_button'), 'menubar': ('navigation.menu_bar', 'menu_bar'), 'menu': ('overlay.menu', 'popup_menu'),
    'tooltip': ('overlay.tooltip', 'hint'), 'tree': ('tree_adapter', 'tree_list'), 'listview': ('datagrid (header, rows)', 'data_grid'),
    'syslink': ('control.text (link)', 'label'), 'datepicker': ('control.picker', 'date_edit'), 'monthcal': ('control.picker (calendar)', 'date_edit'),
    'window': ('overlay.dialog (chrome)', 'dialog'), 'dialog': ('overlay.dialog (chrome)', 'dialog'), 'messagebox': ('overlay.dialog', 'dialog'),
    'taskdialog': ('overlay.dialog', 'dialog'),
}
SCALE = {96: '1x', 144: '1.5x', 192: '2x'}
rows, ctl = [], {}
for theme in ('light', 'dark'):
    for idx in sorted(glob.glob(os.path.join(src, f'index-{theme}-*.tsv'))):
        os.makedirs(os.path.join(dest, theme), exist_ok=True)
        # last line wins when a name was captured twice (re-runs append nothing: the gallery rewrites the index)
        seen = {}
        for ln in open(idx, encoding='utf-8'):
            p = ln.rstrip('\n').split('\t')
            if len(p) == 5: seen[p[0]] = p
        for name, p in seen.items():
            w, h, dpi, rects = int(p[1]), int(p[2]), int(p[3]), json.loads(p[4])
            sc = SCALE[dpi]; bmp = os.path.join(src, theme, f'{name}@{sc}.bmp')
            if not os.path.exists(bmp): continue
            im = Image.open(bmp).convert('RGB')
            rel = f'{theme}/{name}@{sc}.png'; im.save(os.path.join(dest, rel), optimize=True)
            same = ''
            for rest in (name.rsplit('-', 1)[0] + '-rest', name.replace('-hover', '-rest').replace('-pressed', '-rest').replace('-focus', '-rest')):
                if rest != name and rest in seen:
                    rb = os.path.join(src, theme, f'{rest}@{sc}.bmp')
                    if os.path.exists(rb) and ImageChops.difference(im, Image.open(rb).convert('RGB')).getbbox() is None:
                        same = rest; break
            key = name.split('-')[0]; neper = NEPER.get(key, ('', ''))
            state = name[len(key) + 1:]
            rows.append([rel, theme, sc, key, state, f'{im.width}x{im.height}', neper[0], neper[1], ('PIXEL-IDENTICAL to ' + same + ': no distinct look in this capture') if same else ''])
            ctl[rel] = {'size': [im.width, im.height], 'dpi': dpi, 'controls': rects}
rows.sort()
with open(os.path.join(dest, 'manifest.csv'), 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL); w.writerow(['File', 'Theme', 'Scale', 'Control', 'State', 'Size', 'NeperControl', 'StatusId', 'Notes']); w.writerows(rows)
json.dump(ctl, open(os.path.join(dest, 'controls.json'), 'w', encoding='utf-8'), indent=1)
print(len(rows), 'captures')
