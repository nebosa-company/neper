"""Round 22 (worker lc) comparer: the l3 sheets with only TEXT glyphs set apart (icons, ticks, chevrons, triangles count).

  python -I scripts/linux_cmp_lc.py [sheet ...]       strict per-cell numbers for both schemes (flat reference pixels off; all pixels off)
  python -I scripts/linux_cmp_lc.py -v [sheet ...]    per cell
Needs the l3 composites (python -I scripts/linux_cmp_l3.py compose <sheet>) and the committed sheets.
"""
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import linux_cmp_l3 as m

ICONS = {
    "status_bar": {"headerbar-subtitle": [(15, 15, 30, 30), (275, 16, 290, 29), (316, 16, 330, 30), (353, 16, 367, 30), (390, 16, 404, 30)]},
    "page_control": {"adw-tabbar": [(90, 17, 101, 28)], "adw-viewswitcher": [(22, 3, 39, 21), (137, 3, 155, 21)]},
    "popup_menu": {"menu-view": [(41, 34, 57, 52), (157, 177, 166, 193)]},
}
for name, cells in ICONS.items():
    sh = m.SHEETS[name]
    for i, (crop, inks) in enumerate(sh["cells"]):
        if crop in cells:
            sh["cells"][i] = (crop, [r for r in inks if r not in cells[crop]])
# the menu button's popover with its arrow (the library's first capture; not in the l3 sheets): the 181 x 290 crop in a 210 x 300 cell
m.sheet("popup_menu-arrow", 1, 210, 300, [("popover-menu-open", [(40, y - 10, 108, y + 10) for y in (56, 88, 120, 165, 197, 242)])])

# ---- the l4 sheets (tree_list, list_box, check_list_box, data_grid) with no art rectangle: triangles and ticks count ----
def l4(names, png=False):
    import linux_cmp_l4 as k
    for n in names:
        k.SHEETS[n]["art"] = {}
        k.cmp(n, png)


if __name__ == "__main__" and sys.argv[1:2] == ["l4"]:
    l4(sys.argv[2:] or ["tree_list", "list_box", "check_list_box", "data_grid"], False)
elif __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["heat"]:
        m.heat(args[1], args[2])
        sys.exit(0)
    if args[:1] == ["compose"]:
        for n in args[1:]:
            m.compose(n)
        sys.exit(0)
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    for n in (args or list(m.SHEETS)):
        for scheme in ("light", "dark"):
            m.measure(n, scheme, verbose)
