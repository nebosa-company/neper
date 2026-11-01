"""Rebuilds ref/windows-1to1/toolbar_button_row.png and toolbar_button_hot.png from the true 1:1 captures (`python -I scripts/looks_toolbar_ref1to1.py`).

looks_ref1to1.py cannot place these two: their cells are not exact crops of one old capture. The row cell is the main window's toolbar
row (dialogs/main-window@1x.png at (8, 84), 657 x 26) at (12, 32) of the sheet; each hot cell (1314 x 26, 56 px apart) is the same
26 rows of a hover grab (states/hover-toolbar-button-*) shifted so that the hovered button sits at the cell's centre, as
examples/looks/toolbar_button.e `build_hot` does (the pointer's button is at x `xs` of the window, 23 wide); columns outside the window's
client (x < 8 or >= 792) stay the face. The rest of each sheet is the old composite."""
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
Image.fromarray(row).save(R + 'ref/windows-1to1/toolbar_button_row.png')
hot = load(R + 'ref/windows/toolbar_button_hot.png')
for i, (n, x) in enumerate(zip(NAMES, XS)):
    cap = load(S + 'hover-toolbar-button-' + n + '@1x.png')[84:110]
    cell = np.full((26, 1314, 3), 240, np.uint8)
    for cx in range(1314):
        sx = x + 11 - 657 + cx
        if 8 <= sx < 792:
            cell[:, cx] = cap[:, sx]
    hot[32 + 56 * i:58 + 56 * i, 12:1326] = cell
Image.fromarray(hot).save(R + 'ref/windows-1to1/toolbar_button_hot.png')
