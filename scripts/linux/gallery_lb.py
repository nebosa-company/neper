#!/usr/bin/env python3
"""Round 22, worker lb: re-capture the GTK states of button, checkbox, radio, label, group box, button edit, progress bar, vertical grid,
dialog and toolbar button with a long settle after the state flags are set (libadwaita's 200 ms outline / background transitions
were still running at gallery.py's 180 ms, so focus rings, hover and active fills were captured part-faded). Run in WSL from the repo root:
  xvfb-run -a -s "-screen 0 1280x1024x24" python3 scripts/linux/gallery_lb.py [outdir]
Same file names as gallery.py; the default outdir is docs/ui/looks/ref/linux (overwrites those states)."""
import os, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else "docs/ui/looks/ref/linux"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.argv = sys.argv[:1]
import gallery as g
from gallery import Gtk, Adw, F, settle, to_texture, apply_flags

MINE = {"button", "checkbox", "radio", "radio_group", "label", "group_box", "button_edit", "progress_bar", "vertical_grid", "toolbar_button"}
SKIP = {"spinner"}  # animated


def main():
    Adw.init()
    Gtk.Settings.get_default().set_property("gtk-font-name", "Cantarell 11")
    sm = Adw.StyleManager.get_default()
    n = 0
    for scheme, cs in (("light", Adw.ColorScheme.FORCE_LIGHT), ("dark", Adw.ColorScheme.FORCE_DARK)):
        sm.set_color_scheme(cs)
        os.makedirs(f"{OUT}/{scheme}", exist_ok=True)
        win = Adw.Window(default_width=560, default_height=420)
        win.present()
        settle()
        bg = win.get_style_context().lookup_color("window_bg_color")
        bg = bg[1] if bg[0] else None
        for neper, name, build, flags, note in g.ROWS:
            if neper not in MINE or name in SKIP or name == "alert-dialog":
                continue
            wd = build()
            pad = Gtk.Box(margin_top=12, margin_bottom=12, margin_start=12, margin_end=12, halign=Gtk.Align.START, valign=Gtk.Align.START)
            pad.append(wd)
            win.set_content(pad)
            settle(8)
            if flags != F.NORMAL:
                apply_flags(wd, flags)
                settle(14)
            for s in (1, 2):
                to_texture(pad, s, bg).save_to_png(f"{OUT}/{scheme}/{name}@{s}x.png")
            n += 1
        win.destroy()
    print(n, "captures written to", OUT)


if __name__ == "__main__":
    main()
