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


def walk(w):
    yield w
    c = w.get_first_child()
    while c:
        yield from walk(c)
        c = c.get_next_sibling()


def menu_model(kind):
    m = Gio.Menu()
    def item(label, action, accel=None, target=None):
        it = Gio.MenuItem.new(label, action)
        if target:
            it.set_action_and_target_value(action, GLib.Variant.new_string(target))
        if accel:
            it.set_attribute_value("accel", GLib.Variant.new_string(accel))
        return it
    if kind == "edit":
        s1 = Gio.Menu(); s1.append_item(item("Undo", "m.undo", "<Control>z")); s1.append_item(item("Redo", "m.redo", "<Control><Shift>z"))
        s2 = Gio.Menu(); s2.append_item(item("Cut", "m.cut", "<Control>x")); s2.append_item(item("Copy", "m.copy", "<Control>c")); s2.append_item(item("Paste", "m.paste", "<Control>v"))
        s3 = Gio.Menu(); s3.append_item(item("Select All", "m.all", "<Control>a"))
        for sec in (s1, s2, s3):
            m.append_section(None, sec)
    else:
        s1 = Gio.Menu(); s1.append_item(item("Show Toolbar", "m.toolbar")); s1.append_item(item("Show Sidebar", "m.sidebar"))
        s2 = Gio.Menu()
        s2.append_item(item("as Icons", "m.view", None, "icons")); s2.append_item(item("as List", "m.view", None, "list"))
        sub = Gio.Menu(); sub.append("Name", "m.undo"); s2.append_submenu("Sort By", sub)
        s3 = Gio.Menu(); s3.append_item(item("Full Screen", "m.full", "F11"))
        for sec in (s1, s2, s3):
            m.append_section(None, sec)
    return m


def actions():
    g = Gio.SimpleActionGroup()
    for n in ("undo", "cut", "copy", "paste", "all", "full"):
        g.add_action(Gio.SimpleAction.new(n, None))
    redo = Gio.SimpleAction.new("redo", None); redo.set_enabled(False); g.add_action(redo)
    g.add_action(Gio.SimpleAction.new_stateful("toolbar", None, GLib.Variant.new_boolean(True)))
    g.add_action(Gio.SimpleAction.new_stateful("sidebar", None, GLib.Variant.new_boolean(False)))
    g.add_action(Gio.SimpleAction.new_stateful("view", GLib.VariantType.new("s"), GLib.Variant.new_string("icons")))
    return g


def popup_menu(kind, hover=""):
    def b():
        mb = Gtk.MenuButton(label="Menu")
        pop = Gtk.PopoverMenu.new_from_model(menu_model(kind))
        pop.set_has_arrow(False)
        mb.set_popover(pop)
        mb.insert_action_group("m", actions())
        mb._open = True
        mb._hover = hover
        return mb
    return b


ROWS = [("hint", "tooltip-real", tooltip_real, F.NORMAL, "tooltip.background > box > label as GtkTooltipWindow builds it"),
        ("popup_menu", "menu-edit", popup_menu("edit"), F.NORMAL, "GtkPopoverMenu, no arrow: shortcuts, a disabled row, sections"),
        ("popup_menu", "menu-edit-hover", popup_menu("edit", "Paste"), F.NORMAL, "the same with the Paste row hovered"),
        ("popup_menu", "menu-edit-active", popup_menu("edit", "Paste:active"), F.NORMAL, "the same with the Paste row pressed"),
        ("popup_menu", "menu-view", popup_menu("view"), F.NORMAL, "checks, radios, a submenu and an accelerator"),
        ("menu_bar", "menubar-selected", menubar(1), F.NORMAL, "the second title (Edit) in the :selected state a hover or open menu gives")]


def popover_texture(mb, scale):
    """The popover of a menu button on its own surface; no window is active under Xvfb, so the backdrop flag is cleared."""
    pop = mb.get_popover()
    mb.popup()
    G.settle(10)
    for w in walk(pop):
        w.unset_state_flags(F.BACKDROP)
    # the first row takes the keyboard selection when the popover opens: clear it, then set the asked state on one row
    for w in walk(pop):
        if w.get_css_name() == "modelbutton":
            w.unset_state_flags(F.SELECTED | F.FOCUSED | F.FOCUS_VISIBLE | F.PRELIGHT | F.ACTIVE)
            if mb._hover and w.get_property("text") == mb._hover.split(":")[0]:
                w.set_state_flags(F.PRELIGHT | (F.ACTIVE if mb._hover.endswith(":active") else F.NORMAL), False)
    G.settle(4)
    tex = G.to_texture(pop, scale)
    mb.popdown()
    G.settle(3)
    return tex


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
            if getattr(wd, "_open", False):
                texs = {s: popover_texture(wd, s) for s in (1, 2)}
            else:
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
