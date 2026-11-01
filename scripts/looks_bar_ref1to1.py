"""Rebuilds the bar reference sheets looks_ref1to1.py cannot place (`python -I scripts/looks_bar_ref1to1.py`): ref/windows-1to1/toolbar_button_row.png and toolbar_button_hot.png, and the Reports and Search cells of menu_bar_open_reports.png and menu_bar_open_search.png, from the true 1:1 captures.

looks_ref1to1.py cannot place these two: their cells are not exact crops of one old capture. The row cell is the main window's toolbar
row (dialogs/main-window@1x.png at (8, 84), 657 x 26) at (12, 32) of the sheet; each hot cell (1314 x 26, 56 px apart) is the same
26 rows of a hover grab (states/hover-toolbar-button-*) shifted so that the hovered button sits at the cell's centre, as
examples/looks/toolbar_button.e `build_hot` does (the pointer's button is at x `xs` of the window, 23 wide); columns outside the window's
client (x < 8 or >= 792) stay the face. The rest of each sheet is the old composite. The 26th row of every cell is the next element of the
window under the bar (a #828282 edge, 130), not the control: the bar is 25 rows, so that row is left the face in all three sheets
(toolbar_button.png as looks_ref1to1.py built it, too)."""
import numpy as np
from PIL import Image
R = 'docs/ui/looks/'
S = R + 'ref/windows-1to1/states/'
NAMES = ['cards-expand', 'cards-f', 'search-filter', 'search-filter-plus', 'search-binoculars', 'help-home', 'help-discord',
         'search-filter-pressed', 'search-binoculars-pressed']
XS = [384, 407, 466, 489, 512, 617, 640, 466, 512]


def load(p):
    return np.array(Image.open(p).convert('RGB'))


row = load(R + 'ref/windows/toolbar_button_row.png')
main = load(R + 'ref/windows-1to1/dialogs/main-window@1x.png')
row[32:58, 12:669] = main[84:110, 8:665]
row[57, 12:669] = 240
Image.fromarray(row).save(R + 'ref/windows-1to1/toolbar_button_row.png')
hot = load(R + 'ref/windows/toolbar_button_hot.png')
for i, (n, x) in enumerate(zip(NAMES, XS)):
    cap = load(S + 'hover-toolbar-button-' + n + '@1x.png')[84:110]
    cell = np.full((26, 1314, 3), 240, np.uint8)
    for cx in range(1314):
        sx = x + 11 - 657 + cx
        if 8 <= sx < 792:
            cell[:, cx] = cap[:, sx]
    cell[25] = 240
    hot[32 + 56 * i:58 + 56 * i, 12:1326] = cell
Image.fromarray(hot).save(R + 'ref/windows-1to1/toolbar_button_hot.png')
one = load(R + 'ref/windows-1to1/toolbar_button.png')
one[57, 12:459] = 240
Image.fromarray(one).save(R + 'ref/windows-1to1/toolbar_button.png')
# the two open-menu bars whose cell has no 1:1 twin of its hover-switch grab: the same bar is in menu-bar-open-title-<menu> (the title open)
for menu in ('reports', 'search'):
    sheet = load(R + 'ref/windows-1to1/menu_bar_open_%s.png' % menu)
    cap = load(S + 'menu-bar-open-title-%s@1x.png' % menu)
    sheet[32:58, 12:794] = cap[31:57, 8:790]
    Image.fromarray(sheet).save(R + 'ref/windows-1to1/menu_bar_open_%s.png' % menu)
