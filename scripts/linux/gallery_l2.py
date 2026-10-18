#!/usr/bin/env python3
"""Round 20, worker l2: extra GTK reference states for the edit controls that gallery.py's forced flags do not reach
(an entry's focus ring needs FOCUS_WITHIN). Run in WSL from the repo root:
  xvfb-run -a -s "-screen 0 1280x1024x24" python3 scripts/linux/gallery_l2.py [outdir]
Writes docs/ui/looks/ref/linux/{light,dark}/<name>@{1x,2x}.png and manifest-l2.csv (same columns as manifest.csv)."""
import csv, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.argv = sys.argv[:1] + sys.argv[1:2]
import gallery as g
from gallery import Gtk, Adw, F, settle, to_texture, kids, sized, css, box
OUT = sys.argv[1] if len(sys.argv) > 1 else "docs/ui/looks/ref/linux"
ROWS = []


def reg(neper, name, build, flags=F.NORMAL, note=""):
    ROWS.append((neper, name, build, flags, note))


def deep(w):
    if w.get_css_name() == "button":  # a spin button's arrows keep their own state
        return
    yield w
    for c in kids(w):
        yield from deep(c)


def arrow(spin, which):
    return next(c for c in kids(spin) if c.get_css_name() == "button" and c.has_css_class(which))


def spin50():
    s = Gtk.SpinButton.new_with_range(0, 100, 1)
    s.set_value(50)
    return sized(s, 120)


class OnArrow:
    """flags for one arrow of a spin button (the pointer is over or presses it)"""
    def __init__(self, which):
        self.which = which


FOCUS = F.FOCUS_WITHIN | F.FOCUSED | F.FOCUS_VISIBLE


def entry():
    return sized(Gtk.Entry(text="Some text"), 200)


def spin():
    return sized(Gtk.SpinButton.new_with_range(0, 100, 1), 120)


reg("text_edit", "entry-focus-ring", entry, FOCUS, "FOCUS_WITHIN on the entry and its text child")
reg("text_edit", "entry-error-focus", lambda: sized(css(Gtk.Entry(text="Error"), "error"), 200), FOCUS)
reg("text_edit", "entry-selected", entry, F.NORMAL, "select_region(0,-1) with focus")
reg("spin_edit", "spin-focus-ring", spin, FOCUS, "FOCUS_WITHIN on the spin button and its text child")
reg("spin_edit", "spin50-normal", spin50, F.NORMAL, "value 50: both arrows enabled")
reg("spin_edit", "spin50-hover-up", spin50, OnArrow("up"), "pointer over the + arrow")
reg("spin_edit", "spin50-hover-down", spin50, OnArrow("down"), "pointer over the - arrow")
reg("spin_edit", "spin50-active-up", spin50, OnArrow("up-active"), "+ arrow pressed")
reg("spin_edit", "spin50-active-down", spin50, OnArrow("down-active"), "- arrow pressed")
reg("spin_edit", "spin50-focus-ring", spin50, FOCUS, "FOCUS_WITHIN on the spin button and its text, arrows left alone")
reg("spin_edit", "spin50-disabled", spin50, F.INSENSITIVE)
reg("spin_edit", "spin-max", lambda: (lambda s: (s.set_value(100), sized(s, 120))[1])(Gtk.SpinButton.new_with_range(0, 100, 1)), F.NORMAL, "value 100: the + arrow disabled")
reg("mask_edit", "entry-mask-focus", lambda: sized(Gtk.Entry(text="(555) 010-1234"), 200), FOCUS)
reg("mask_edit", "entry-mask-disabled", lambda: sized(Gtk.Entry(text="(555) 010-1234"), 200), F.INSENSITIVE)
reg("memo", "textview-focus", lambda: g.memo(), FOCUS)
reg("memo", "textview-disabled", lambda: g.memo(), F.INSENSITIVE)
reg("combo_box", "combo-entry-focus", lambda: g.combo_entry(), FOCUS)
reg("combo_box", "combo-entry-disabled", lambda: g.combo_entry(), F.INSENSITIVE)


def main():
    Adw.init()
    Gtk.Settings.get_default().set_property("gtk-font-name", "Cantarell 11")
    sm = Adw.StyleManager.get_default()
    manifest = []
    for scheme, cs in (("light", Adw.ColorScheme.FORCE_LIGHT), ("dark", Adw.ColorScheme.FORCE_DARK)):
        sm.set_color_scheme(cs)
        os.makedirs(f"{OUT}/{scheme}", exist_ok=True)
        win = Adw.Window(default_width=560, default_height=420)
        win.present()
        settle()
        bg = win.get_style_context().lookup_color("window_bg_color")
        bg = bg[1] if bg[0] else None
        for neper, name, build, flags, note in ROWS:
            wd = build()
            pad = Gtk.Box(margin_top=12, margin_bottom=12, margin_start=12, margin_end=12, halign=Gtk.Align.START, valign=Gtk.Align.START)
            pad.append(wd)
            win.set_content(pad)
            settle()
            if name.endswith("selected"):
                wd.grab_focus()
                wd.select_region(0, -1)
                settle(12)
            if not name.endswith("selected"):
                for n in deep(wd):
                    if isinstance(n, Gtk.Text):
                        n.select_region(0, 0)
                win.set_focus(None)
                settle(3)
            if isinstance(flags, OnArrow):
                which = flags.which
                if which.endswith("-active"):
                    arrow(wd, which.split("-")[0]).set_state_flags(F.PRELIGHT | F.ACTIVE, False)
                else:
                    arrow(wd, which).set_state_flags(F.PRELIGHT, False)
                settle(12)
            elif flags != F.NORMAL:
                for n in deep(wd):
                    n.set_state_flags(F(int(flags) & ~int(F.INSENSITIVE)) if not (flags & F.INSENSITIVE) else F.NORMAL, False)
                if flags & F.INSENSITIVE:
                    wd.set_sensitive(False)
                settle(12)  # past libadwaita's 200 ms outline transition
            for s in (1, 2):
                tex = to_texture(pad, s, bg)
                tex.save_to_png(f"{OUT}/{scheme}/{name}@{s}x.png")
            manifest.append((scheme, neper, name, f"{scheme}/{name}@1x.png", f"{scheme}/{name}@2x.png", tex.get_width() // 2, tex.get_height() // 2, note))
        win.destroy()
    with open(f"{OUT}/manifest-l2.csv", "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["scheme", "neper_control", "name", "png_1x", "png_2x", "w_1x", "h_1x", "note"])
        wr.writerows(manifest)
    print(len(manifest), "entries")


if __name__ == "__main__":
    main()
