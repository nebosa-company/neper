#!/usr/bin/env python3
"""Dump libadwaita's named colours (light and dark) as markdown rows. Run via run.sh-style xvfb-run."""
import os
os.environ.setdefault("GDK_BACKEND", "x11")
import gi
gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw
Adw.init()
names = ["window_bg_color", "window_fg_color", "view_bg_color", "view_fg_color", "headerbar_bg_color", "headerbar_fg_color",
         "headerbar_border_color", "headerbar_backdrop_color", "headerbar_shade_color", "card_bg_color", "card_fg_color",
         "card_shade_color", "dialog_bg_color", "dialog_fg_color", "popover_bg_color", "popover_fg_color", "popover_shade_color",
         "sidebar_bg_color", "sidebar_fg_color", "accent_color", "accent_bg_color", "accent_fg_color",
         "destructive_color", "destructive_bg_color", "destructive_fg_color", "success_color", "success_bg_color",
         "warning_color", "warning_bg_color", "error_color", "error_bg_color", "borders", "scrollbar_outline_color",
         "shade_color", "thumbnail_bg_color"]
win = Adw.Window(); win.present()
rows = {}
for scheme, cs in (("light", Adw.ColorScheme.FORCE_LIGHT), ("dark", Adw.ColorScheme.FORCE_DARK)):
    Adw.StyleManager.get_default().set_color_scheme(cs)
    ctx = win.get_style_context()
    import gi.repository.GLib as G
    for _ in range(50): G.MainContext.default().iteration(False)
    for n in names:
        ok, c = ctx.lookup_color(n)
        rows.setdefault(n, {})[scheme] = ("#%02x%02x%02x" % tuple(round(v * 255) for v in (c.red, c.green, c.blue)) + ("" if c.alpha > .999 else f" a={c.alpha:.2f}")) if ok else "-"
print("| name | light | dark |\n|---|---|---|")
for n in names: print(f"| `@{n}` | {rows[n]['light']} | {rows[n]['dark']} |")
