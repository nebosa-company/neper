#!/usr/bin/env python3
"""Extra GTK4 / libadwaita reference states for the round 20 Linux looks (worker l3); same method as gallery.py.

Run inside WSL from the repo root:  sh scripts/linux/run_l3.sh [name-substring]
Writes docs/ui/looks/ref/linux/{light,dark}/<name>@{1x,2x}.png and appends rows to manifest-l3.csv (the shared
manifest.csv is gallery.py's output and is left alone).
"""
import csv, os, sys
os.environ.setdefault("GDK_BACKEND", "x11")
os.environ.setdefault("GSK_RENDERER", "cairo")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gi
for n, v in (("Gtk", "4.0"), ("Adw", "1"), ("Gio", "2.0")):
    gi.require_version(n, v)
from gi.repository import Gtk, Adw, GLib, Gio
import gallery as G

ONLY = sys.argv[1] if len(sys.argv) > 1 else ""
OUT = "docs/ui/looks/ref/linux"
F = Gtk.StateFlags


class Tooltip(Gtk.Box):
    """GtkTooltipWindow's node tree: tooltip.background > box > label (the CSS node name is what the stylesheet selects)."""
    __gtype_name__ = "L3Tooltip"


Tooltip.set_css_name("tooltip")


def tooltip_real():
    t = Tooltip(orientation=Gtk.Orientation.HORIZONTAL)
    t.add_css_class("background")
    inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
    inner.append(Gtk.Label(label="Tooltip text"))
    t.append(inner)
    return t


def kids(w):
    c = w.get_first_child()
    while c:
        yield c
        c = c.get_next_sibling()


def menubar(selected=-1):
    def b():
        m = Gio.Menu()
        for top in ("File", "Edit", "Help"):
            sub = Gio.Menu()
            sub.append("Item", "app.x")
            m.append_submenu(top, sub)
        bar = Gtk.PopoverMenuBar.new_from_model(m)
        bar._select = selected
        return bar
    return b


ROWS = [("hint", "tooltip-real", tooltip_real, F.NORMAL, "tooltip.background > box > label as GtkTooltipWindow builds it"),
        ("menu_bar", "menubar-selected", menubar(1), F.NORMAL, "the second title (Edit) in the :selected state a hover or open menu gives")]


def main():
    Adw.init()
    Gtk.Settings.get_default().set_property("gtk-font-name", "Cantarell 11")
    sm = Adw.StyleManager.get_default()
    rows = []
    for scheme, cs in (("light", Adw.ColorScheme.FORCE_LIGHT), ("dark", Adw.ColorScheme.FORCE_DARK)):
        sm.set_color_scheme(cs)
        os.makedirs(f"{OUT}/{scheme}", exist_ok=True)
        win = Adw.Window(default_width=560, default_height=420)
        win.present()
        G.settle()
        bg = win.get_style_context().lookup_color("window_bg_color")
        bg = bg[1] if bg[0] else None
        for neper, name, build, flags, note in ROWS:
            if ONLY and ONLY not in name:
                continue
            wd = build()
            pad = Gtk.Box(halign=Gtk.Align.START, valign=Gtk.Align.START)
            pad.append(wd)
            win.set_content(pad)
            G.settle()
            if getattr(wd, "_select", -1) >= 0:
                items = list(kids(wd))
                items[wd._select].set_state_flags(F.SELECTED, False)
                G.settle(3)
            texs = {s: G.to_texture(pad, s, None) for s in (1, 2)}
            for s, tex in texs.items():
                tex.save_to_png(f"{OUT}/{scheme}/{name}@{s}x.png")
            rows.append((scheme, neper, name, f"{scheme}/{name}@1x.png", f"{scheme}/{name}@2x.png", texs[1].get_width(), texs[1].get_height(), note))
        win.destroy()
    path = f"{OUT}/manifest-l3.csv"
    old = []
    if os.path.exists(path):
        with open(path, newline="") as f:
            old = [r for r in csv.reader(f)][1:]
    keep = [r for r in old if not any(r[0] == n[0] and r[2] == n[2] for n in rows)]
    with open(path, "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["scheme", "neper_control", "name", "png_1x", "png_2x", "w_1x", "h_1x", "note"])
        wr.writerows(keep + rows)
    print(len(rows), "entries written to", OUT)


if __name__ == "__main__":
    main()
