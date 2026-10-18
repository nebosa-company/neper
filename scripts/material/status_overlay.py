"""Writes docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round23-mat.json from the strict comparison (scripts/material/cmp.py).

  python -I scripts/material/status_overlay.py          (from the repository root, after the material sheets are rendered)

A cell passes when off + shadow is at most 0.3 % of its structural pixels (40 at least): glyph ink is excluded by the metric
and reported separately; `shadow` is every pixel outside the control's box (drawn shadows, state layers). A look is `matched`
when every compared state passes in that palette AND every reference captured for the control has a cell on a sheet; a
reference without a cell, or a failing cell, makes it `review`; a control with no Material Web reference to compare with
stays `started`.
"""
import contextlib
import csv
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cmp  # noqa: E402
from sheets import SHEETS  # noqa: E402

ROOT = cmp.ROOT
# control id -> (sheets compared, reference name prefixes, screenshot, what Material Web lacks or Neper differs in)
CONTROLS = {
    "button": (["button", "button_icon"], ["button-"], "material/button.png", []),
    "toolbar_button": (["fab"], ["icon-button-"], "material/fab.png", ["The icon is Neper's glyph, not the Material icon (glyph ink is excluded from the metric)"]),
    "fab": (["fab"], ["fab-"], "material/fab.png", ["Extended FAB: a 1 to 2 px difference of the shadow at its ends (fitted shade, level 3 and 4)"]),
    "checkbox": (["checkbox"], ["checkbox-"], "material/checkbox.png", ["The error check box is the M3 error tokens applied to Material Web's element (the library defines them but draws no error state)"]),
    "radio": (["radio"], ["radio-"], "material/radio.png", ["M3 defines no error state for a radio button: the sheet's Error column has no reference"]),
    "switch": (["switch"], ["switch-"], "material/switch.png", []),
    "text_edit": (["text_field"], ["text-field-"], "material/text_field.png", ["The caret is not compared (the reference caret is hidden: it blinks)", "Hover is reached through a region round the field (the runtime hovers regions, not editors)"]),
    "combo_box": (["combo_box"], ["select-"], "material/combo_box.png", ["The drop-down arrow is Neper's chevron, Material's is a filled triangle (icon ink)", "The open list is not compared"]),
    "chip": (["chips"], ["chip-"], "material/chips.png", ["Input chip: the remove icon is Neper's cross, drawn bolder than Material's", "Chip positions are fractional in the sheet cell (odd widths), so 1 px rims differ"]),
    "progress_bar": (["progress"], ["progress-"], "material/progress.png", ["Indeterminate progress and the buffer, four-colour and disabled linear forms are not compared"]),
    "page_control": (["tabs"], ["tabs-"], "material/tabs.png", ["Primary tabs: the label text is 1 px off Material's (glyph ink)", "Tabs with icons use Neper's glyphs"]),
    "popup_menu": (["menu", "menu_hover"], ["menu-"], "material/menu.png", ["Rows are 56 dp, as md-menu draws them (the M3 spec says 48)", "Shortcut text sits where Material Web puts its trailing supporting text (label-small)"]),
    "list_box": (["list"], ["list-item-"], "material/list.png", ["Material Web has no selected list item and no three-line item: those sheet cells are not compared", "Pressed layer is one level off Material Web's"]),
    "dialog": (["dialog", "dialog_icon"], ["dialog-"], "material/dialog.png", ["The paragraph wraps one word earlier in Material Web (a 1 px wider text run)"]),
    "snackbar": (["snackbar"], ["snackbar-"], "material/snackbar.png", ["Hovered and pressed action are not compared (the pointer of the capture is not over the action)", "Material Web has no snackbar: the reference is plain CSS from the specification with md-elevation"]),
    "navigation_bar": (["navigation_bar"], ["navigation-bar-"], "material/navigation_bar.png", ["Material Web has no navigation bar: the reference is plain CSS from the specification", "Badge placement on the icon is the spec CSS's guess"]),
    "top_app_bar": (["app_bar"], ["app-bar-"], "material/app_bar.png", ["Material Web has no app bar: the reference is plain CSS from the specification", "Medium and large app bars are not compared"]),
    "search_bar": (["search_bar"], ["search-bar-"], "material/search_bar.png", ["Material Web has no search bar: the reference is plain CSS from the specification", "Focused states are not compared (caret)", "With text: Neper's clear button is 40 dp and drawn with its own glyph"]),
    "badge": (["badge"], ["badge-"], "material/badge.png", ["Material Web has no badge: the reference is plain CSS from the specification; the badge's offset on its icon follows that CSS"]),
    "hint": (["tooltip"], ["tooltip-"], "material/tooltip.png", ["The sheet's anchor button lies under the plain tooltip's crop", "The rich tooltip is 20 dp shorter than the specification's"]),
    "slider": ([], ["slider-"], "material/slider.png", ["Neper draws the M3 Expressive slider (vertical bar handle, gaps); Material Web draws the classic circle handle: not converted, not compared"]),
    "date_picker": ([], ["date-picker-"], "material/date_picker.png", ["Material Web has no date picker and the specification CSS is only a sketch: not compared"]),
}


def refs_of(prefixes):
    names = set()
    with open(os.path.join(cmp.REF, "manifest.csv")) as f:
        for r in csv.DictReader(f):
            if r["scheme"] == "light" and any(r["name"].startswith(p) for p in prefixes):
                names.add(r["name"])
    return names


def run(sheets, dark):
    out = []
    for s in sheets:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            out += cmp.run(s, dark, None, None)
    return out


def main():
    overlay = {}
    for cid, (sheets, prefixes, shot, gaps) in CONTROLS.items():
        captured = refs_of(prefixes)
        looks = {}
        for dark in (False, True):
            key = "material_dark" if dark else "material"
            shot_here = shot.replace("material/", "material-dark/") if dark else shot
            if not sheets:
                looks[key] = {"status": "started", "screenshot": shot_here, "notes": "No comparison: see the gaps.", "gaps": gaps + ["%d reference states captured in docs/ui/looks/ref/material" % len(captured)]}
                continue
            res = run(sheets, dark)
            compared = {r[0] for r in res}
            failing = [r for r in res if r[4] + r[7] > max(40, 0.003 * r[3])]
            uncovered = sorted(captured - compared)
            worst = max([r[4] + r[7] for r in res] or [0])
            glyph = max([r[5] - r[4] for r in res] or [0])
            status = "matched" if not failing and not uncovered else "review"
            notes = ("Compared with Material Web (docs/ui/looks/ref/material) at 100 %% on the strict metric (a reference structural pixel is off when ours differs by more than 2 levels; "
                     "text and icon ink within 2 px excluded, glyph-counted separately; every pixel outside the control's box compared, so shadows and state layers count): "
                     "%d states compared, %d over the line (off + outside above 0.3 %% of the structural pixels); worst state %d px off, worst glyph-only count %d px." % (len(res), len(failing), worst, glyph))
            g = list(gaps)
            if failing:
                g.append("Over the line: " + ", ".join("%s (%d)" % (r[0], r[4] + r[7]) for r in failing[:12]) + (" and more" if len(failing) > 12 else ""))
            if uncovered:
                g.append("Reference states with no sheet cell: " + ", ".join(uncovered[:10]) + (" and %d more" % (len(uncovered) - 10) if len(uncovered) > 10 else ""))
            g.append("Evidence: Material Web 1.x rendered in Chromium (focus is the 10 % state layer, pressed 10 %, M3 tracking set to zero as Neper's text engine has no letter spacing); no Android device capture")
            looks[key] = {"status": status, "screenshot": shot_here, "notes": notes, "gaps": g}
        overlay[cid] = {"looks": looks}
    path = os.path.join(ROOT, "docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round23-mat.json")
    with open(path, "w") as f:
        json.dump(overlay, f, indent=1)
        f.write("\n")
    for cid, v in overlay.items():
        print("%-16s %-8s %-8s" % (cid, v["looks"]["material"]["status"], v["looks"]["material_dark"]["status"]))


if __name__ == "__main__":
    main()
