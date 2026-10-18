"""Writes docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round28-mm.json from the strict comparison (scripts/material/cmp.py).

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
    "button": (["button", "button_icon"], ["button-"], "material/button.png", ['Outlined button and icon button focus: the outline is `primary` (M3 tokens, MDC-Android m3_button_outline_color); Material Web has no token for it, so the capture sets its outline-colour token on the focused element', "The elevated button's hover shade is within 3 levels of the capture (a fitted level-2 layer; the fit is a blurred signed distance, Skia's blur of a pill differs by up to 3 levels)"]),
    "toolbar_button": (["fab"], ["icon-button-"], "material/fab.png", ['The captures draw the Material settings icon and Neper draws the same outline (matglyph.e)']),
    "fab": (["fab"], ["fab-"], "material/fab.png", ['The four colour roles (primary, secondary, tertiary, surface) have cells', 'Large FAB hovered: the top rows of the level 4 shade are 4 to 12 levels lighter than the capture (44 px over the line; the bottom matches)', 'The large FAB icon is 36 dp in the specification; the capture drew 24 and was corrected']),
    "checkbox": (["checkbox"], ["checkbox-"], "material/checkbox.png", ["The error check box is the M3 error tokens applied to Material Web's element (the library defines them but draws no error state)"]),
    "radio": (["radio"], ["radio-"], "material/radio.png", ["M3 defines no error state for a radio button: the sheet's Error column has no reference"]),
    "switch": (["switch"], ["switch-"], "material/switch.png", []),
    "text_edit": (["text_field"], ["text-field-"], "material/text_field.png", ['The caret is drawn in its blink-off phase (the captures hide it); it is primary and 2 dp in the runtime', 'Hover is reached through a region round the field (the runtime hovers regions, not editors)', 'An outlined field has its floated label a pixel higher than the line box middle, as the capture has it']),
    "combo_box": (["combo_box"], ["select-"], "material/combo_box.png", ['The arrow is the filled drop-down triangle (md-select); the open list is not compared', 'Empty and value states of both fields have cells']),
    "chip": (["chips"], ["chip-"], "material/chips.png", ['Input chip: the remove icon is the Symbols close the capture draws, 1 px off in x because the sheet centres a chip on a whole pixel but its width is fractional (the 18 to 26 px of each input chip cell)', 'The capture of a focused input chip no longer forces the state layer of its remove button (the focus stands on the chip), and a chip carries enabled, elevated and leading icon forms']),
    "progress_bar": (["progress"], ["progress-"], "material/progress.png", ['Indeterminate progress is not compared (the sweep is time dependent)', 'Linear progress with a buffer, the four-colour form (the same at rest) and the disabled form have cells; Material Web draws a square track end with no stop dot']),
    "page_control": (["tabs"], ["tabs-"], "material/tabs.png", ["Tabs with icons use Neper's glyphs (search, picture, person) where the capture has search, star, person: the 106 glyph-only px", 'Primary tabs share the bar equally and the indicator is as wide as its label (round 26)']),
    "popup_menu": (["menu", "menu_hover"], ["menu-"], "material/menu.png", ['Rows are 56 dp, as md-menu draws them (the M3 spec says 48)', 'Shortcut text sits where Material Web puts its trailing supporting text (label-small)']),
    "list_box": (["list"], ["list-item-"], "material/list.png", ['Material Web has no selected list item and no three-line item: those sheet cells are not compared', "Pressed: the captures hold the settled flat 10 % layer (a wide row's ripple is half grown at the capture time and has been set to its final state); Android draws the same once the ripple has filled the row"]),
    "dialog": (["dialog", "dialog_icon"], ["dialog-"], "material/dialog.png", ['No shade: md-dialog draws none (the capture shows none)', "Words wrap as the capture does only because the sheet's paragraph box is a pixel narrower: Neper's text layout breaks a line on its ink extent, a browser on its advance width", 'The icon dialog icon is the Material search outline']),
    "snackbar": (["snackbar"], ["snackbar-"], "material/snackbar.png", ['The dismiss icon is now the Material close outline', 'Hovered and pressed action are not compared (the pointer of the capture is not over the action)', 'Material Web has no snackbar: the reference is plain CSS from the specification with md-elevation']),
    "navigation_bar": (["navigation_bar"], ["navigation-bar-"], "material/navigation_bar.png", ['Material Web has no navigation bar: the reference is plain CSS from the specification (8 dp gap between destinations, which Neper keeps as 4 dp slack each side of an 88 dp destination: the same centres)', 'Icons are the Material outlines (menu, search, bell, person); a badge sits 15 in (dot) or 12 in and 4 above (count) the 24 dp icon, as the spec CSS has it', 'The labels are glyph-counted text']),
    "top_app_bar": (["app_bar"], ["app-bar-"], "material/app_bar.png", ['Material Web has no app bar: the reference is plain CSS from the specification (the no-icon title now starts 16 dp in, as the specification has it)', 'Medium and large app bars are not compared']),
    "search_bar": (["search_bar"], ["search-bar-"], "material/search_bar.png", ['Material Web has no search bar: the reference is plain CSS from the specification (the leading icon in on-surface, 16 dp before the query)', 'Focused states are not compared (caret)', 'Pressed has a cell']),
    "badge": (["badge"], ["badge-"], "material/badge.png", ['Material Web has no badge: the reference is plain CSS from the specification; the badge sits 15 in (dot) or 12 in and 4 above (count) its icon', 'The control box of the badge on an icon is 26 tall in Neper and 24 in the CSS, so the cell sits 1 px apart']),
    "hint": (["tooltip"], ["tooltip-"], "material/tooltip.png", ['The anchor of the sheet is left unpainted so the crop holds the tooltip alone', "The rich tooltip's width is fractional in Neper and rounded up in the capture (the reference sets it from the text's right edge): a 1 px column on each side differs (218 px of ring)", 'The rich tooltip follows the specification layout (12 above, 16 at the sides with the action label on the text edge, 8 below) and the level 2 shade (the reference CSS had the level 1 values and was corrected)']),
    "slider": (["slider"], ["slider-"], "material/slider.png", ['The Material profile draws the classic M3 circle handle (20 dp, level-1 shade, 40 dp state layer); the Expressive vertical bar stays for every other look', 'The labeled slider (value label while hovered, focused or pressed) and the one with ticks have cells in every state', 'Range hover and press put the state layer on the second handle (the runtime does not say which handle the pointer is on)']),
    "date_picker": (["date_picker"], ["date-picker-"], "material/date_picker.png", ['Material Web has no date picker: the reference is spec-written CSS, re-baselined (round 28) to the M3 modal picker: 360 wide, a 120 dp header with the edit toggle, February 2026 (a Sunday first 28 day month), 48 dp day slots round 40 dp discs, level 3 shade under a 32 % scrim', 'Neper follows it: 360 wide, Sunday first (the sheet sets en-US), 48 dp slots; the remaining pixels are the level 3 shade fit and one text row']),
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
            g.append("Evidence: Material Web 1.x rendered in Chromium with greyscale text and unhinted glyphs (round 26; the earlier captures carried ClearType fringes; round 28 re-captured the corrected cells), focus is the 10 % state layer, pressed 10 %, M3 tracking set to zero as Neper's text engine has no letter spacing; Neper's greyscale text equals that unhinted text to within 2 levels in every text pixel of the dialog and tab cells, so no subpixel mode was added to the text engine; no Android device capture")
            looks[key] = {"status": status, "screenshot": shot_here, "notes": notes, "gaps": g}
        overlay[cid] = {"looks": looks}
    path = os.path.join(ROOT, "docs/ui/looks/status.d/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz-round28-mm.json")
    with open(path, "w") as f:
        json.dump(overlay, f, indent=1)
        f.write("\n")
    for cid, v in overlay.items():
        print("%-16s %-8s %-8s" % (cid, v["looks"]["material"]["status"], v["looks"]["material_dark"]["status"]))


if __name__ == "__main__":
    main()
