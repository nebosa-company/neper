"""Writes docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round26-mm.json from the strict comparison (scripts/material/cmp.py).

  python -I scripts/material/status_overlay.py          (from the repository root, after the material sheets are rendered)

A cell passes when off + shadow + ring is at most 0.3 % of its structural pixels (40 at least): glyph ink is excluded by the metric
and reported separately; `shadow` is every pixel outside the control's box (drawn shadows, state layers); `ring` is the line pixels
(2 px outlines, rings, rules) more than 12 levels off, which the flat count cannot see. A look is `matched`
when every compared state passes in that palette AND every reference captured for the control has a cell on a sheet; a
reference without a cell, or a failing cell, makes it `review`; a control with no Material Web reference to compare with
stays `started`. A control whose reference is spec-written CSS rather than a Material Web capture (SPEC_CSS) is capped at `review`
however close it is, and is `started` when it is far (more than 5 % of its structural pixels off).
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
# Material Web has no such component: the reference is plain CSS written from the M3 specification (scripts/material/gallery.html says so).
SPEC_CSS = {"snackbar", "navigation_bar", "top_app_bar", "search_bar", "badge", "hint", "date_picker"}
# control id -> (sheets compared, reference name prefixes, screenshot, what Material Web lacks or Neper differs in)
CONTROLS = {
    "button": (["button", "button_icon"], ["button-"], "material/button.png", ["Outlined button focus: ours draws the primary outline, the capture the resting grey (Material Web 2.2 has no focus outline token and the capture turns its focus ring off; the M3 token set has primary): a reference and specification ambiguity, left as the M3 tokens have it", "The elevated button's hover shade is within 3 levels of the capture (a fitted level-2 layer)"]),
    "toolbar_button": (["fab"], ["icon-button-"], "material/fab.png", ["The icon is Neper's glyph, not the Material icon (glyph ink is excluded from the metric)"]),
    "fab": (["fab"], ["fab-"], "material/fab.png", ["Extended FAB: a 1 to 2 px difference of the shadow at its ends (fitted shade, level 3 and 4)"]),
    "checkbox": (["checkbox"], ["checkbox-"], "material/checkbox.png", ["The error check box is the M3 error tokens applied to Material Web's element (the library defines them but draws no error state)"]),
    "radio": (["radio"], ["radio-"], "material/radio.png", ["M3 defines no error state for a radio button: the sheet's Error column has no reference"]),
    "switch": (["switch"], ["switch-"], "material/switch.png", []),
    "text_edit": (["text_field"], ["text-field-"], "material/text_field.png", ["Focused cells: the 20 to 25 px off are the caret's column and the label's notch edge (the reference caret is hidden: it blinks)", "Hover is reached through a region round the field (the runtime hovers regions, not editors)"]),
    "combo_box": (["combo_box"], ["select-"], "material/combo_box.png", ["The drop-down arrow is Neper's chevron, Material's is a filled triangle (icon ink)", "The open list is not compared"]),
    "chip": (["chips"], ["chip-"], "material/chips.png", ["Input chip: the remove icon is Neper's cross, drawn larger and bolder than Material Symbols' close, and the focused capture shows a state-layer disc under it that Neper does not draw (the 217 px of chip-input-focus)", "Chip rims: the sheet centres a chip on a whole pixel but a chip's width is fractional (71.15 for Assist), so the right edge differs by a pixel on some rims (ring column)"]),
    "progress_bar": (["progress"], ["progress-"], "material/progress.png", ["Indeterminate progress and the buffer, four-colour and disabled linear forms are not compared"]),
    "page_control": (["tabs"], ["tabs-"], "material/tabs.png", ["Tabs with icons use Neper's glyphs (search, picture, person) where the capture has search, star, person: the 131 glyph-only px", "Primary tabs share the bar equally and the indicator is as wide as its label (round 26)"]),
    "popup_menu": (["menu", "menu_hover"], ["menu-"], "material/menu.png", ["Rows are 56 dp, as md-menu draws them (the M3 spec says 48)", "Shortcut text sits where Material Web puts its trailing supporting text (label-small)"]),
    "list_box": (["list"], ["list-item-"], "material/list.png", ["Material Web has no selected list item and no three-line item: those sheet cells are not compared", "Pressed: Material Web's capture holds a ripple frame (a radial wash that has not reached the ends of the row, up to 4 levels, 467 px light and 1453 px dark): Neper draws the flat 10 % layer"]),
    "dialog": (["dialog", "dialog_icon"], ["dialog-"], "material/dialog.png", ["No shade: md-dialog draws none (the capture shows none; the earlier level-3 shade was a guess)", "Words wrap as the capture does only because the sheet's paragraph box is a pixel narrower: Neper's text layout breaks a line on its ink extent, a browser on its advance width (a line of 300.9 px fits a 300 px box here)", "The icon dialog's icon is Neper's search glyph (7 glyph-only px)"]),
    "snackbar": (["snackbar"], ["snackbar-"], "material/snackbar.png", ["The dismiss icon is Neper's cross (8 px) where the capture has Material Symbols' close (14 px): glyph ink", "Hovered and pressed action are not compared (the pointer of the capture is not over the action)", "Material Web has no snackbar: the reference is plain CSS from the specification with md-elevation"]),
    "navigation_bar": (["navigation_bar"], ["navigation-bar-"], "material/navigation_bar.png", ["Material Web has no navigation bar: the reference is plain CSS from the specification (8 dp gap between destinations, which Neper keeps as 4 dp slack each side of an 88 dp destination: the same centres)", "Icons are Neper's (menu, search, alert, person) where the capture has Material Symbols (home-like menu, search, filled bell, filled person): the 943 glyph-only px", "Badge placement on the icon is the spec CSS's guess"]),
    "top_app_bar": (["app_bar"], ["app-bar-"], "material/app_bar.png", ["Material Web has no app bar: the reference is plain CSS from the specification", "Medium and large app bars are not compared"]),
    "search_bar": (["search_bar"], ["search-bar-"], "material/search_bar.png", ["Material Web has no search bar: the reference is plain CSS from the specification", "Focused states are not compared (caret)", "With text: Neper's clear button is 40 dp and drawn with its own glyph"]),
    "badge": (["badge"], ["badge-"], "material/badge.png", ["Material Web has no badge: the reference is plain CSS from the specification; the badge's offset on its icon follows that CSS"]),
    "hint": (["tooltip"], ["tooltip-"], "material/tooltip.png", ["The sheet's anchor button lies under the plain tooltip's crop", "The rich tooltip is 20 dp shorter than the specification's (title 1 px low, no 4 dp under it, button row 20 dp short: layout not yet reconciled with the CSS); its level-2 shade is drawn now"]),
    "slider": (["slider"], ["slider-"], "material/slider.png", ["The Material profile draws the classic M3 circle handle (20 dp, level-1 shade, 40 dp state layer); the Expressive vertical bar stays for every other look", "Not compared: the labeled value pill and the ticks (the sheet draws neither; the runtime slider's value pill is off in the Material profile)", "Range hover and press put the state layer on the second handle (the runtime does not say which handle the pointer is on)"]),
    "date_picker": (["date_picker"], ["date-picker-"], "material/date_picker.png", ["Material Web has no date picker: the reference is spec-written CSS (360 wide, Sunday first, a 28 day month starting on a Sunday, `Mon, Jun 14` over `June 2021`), compared here against February 2026 (also a Sunday-first 28 day month)", "Neper's modal date picker is 328 wide with 40 dp day cells and Monday first and has the edit pencil; the CSS has 360 wide, 48 dp slots, Sunday first: a structural gap of about 20 000 flat px, not a rendering one"]),
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
            res = [r for r in run(sheets, dark) if any(r[0].startswith(p) for p in prefixes)]
            compared = {r[0] for r in res}
            failing = [r for r in res if r[4] + r[7] + r[9] > max(40, 0.003 * r[3])]
            uncovered = sorted(captured - compared)
            worst = max([r[4] + r[7] + r[9] for r in res] or [0])
            glyph = max([r[5] - r[4] for r in res] or [0])
            status = "matched" if not failing and not uncovered else "review"
            if cid in SPEC_CSS:
                if status == "matched":
                    status = "review"
                far = sum(r[4] + r[7] for r in res) > 0.05 * sum(r[3] for r in res)
                if far:
                    status = "started"
            notes = ("Compared with Material Web (docs/ui/looks/ref/material) at 100 %% on the strict metric (a reference structural pixel is off when ours differs by more than 2 levels; "
                     "text and icon ink within 2 px excluded, glyph-counted separately; every pixel outside the control's box compared, so shadows and state layers count): "
                     "%d states compared, %d over the line (off + outside + ring above 0.3 %% of the structural pixels, 40 at least); worst state %d px, worst glyph-only count %d px." % (len(res), len(failing), worst, glyph))
            if cid in SPEC_CSS:
                notes += " The reference is spec-written CSS, not a Material Web capture, so the status caps at review."
            g = list(gaps)
            if failing:
                g.append("Over the line: " + ", ".join("%s (%d)" % (r[0], r[4] + r[7] + r[9]) for r in failing[:12]) + (" and more" if len(failing) > 12 else ""))
            if uncovered:
                g.append("Reference states with no sheet cell: " + ", ".join(uncovered[:10]) + (" and %d more" % (len(uncovered) - 10) if len(uncovered) > 10 else ""))
            g.append("Evidence: Material Web 1.x rendered in Chromium with greyscale text and unhinted glyphs (round 26; the earlier captures carried ClearType fringes), focus is the 10 % state layer, pressed 10 %, M3 tracking set to zero as Neper's text engine has no letter spacing; Neper's greyscale text equals that unhinted text to within 2 levels in every text pixel of the dialog and tab cells, so no subpixel mode was added to the text engine; no Android device capture")
            looks[key] = {"status": status, "screenshot": shot_here, "notes": notes, "gaps": g}
        overlay[cid] = {"looks": looks}
    path = os.path.join(ROOT, "docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round26-mm.json")
    with open(path, "w") as f:
        json.dump(overlay, f, indent=1)
        f.write("\n")
    for cid, v in overlay.items():
        print("%-16s %-8s %-8s" % (cid, v["looks"]["material"]["status"], v["looks"]["material_dark"]["status"]))


if __name__ == "__main__":
    main()
