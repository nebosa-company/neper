#!/usr/bin/env python3
"""Render real GTK4/libadwaita widgets to PNG, headless (Xvfb), light and dark.

Run inside WSL/Linux from the repo root:  sh scripts/linux/run.sh [outdir] [name-substring]
See scripts/linux/README.md.
"""
import csv, os, sys
os.environ.setdefault("GDK_BACKEND", "x11")
os.environ.setdefault("GSK_RENDERER", "cairo")
import gi
for n, v in (("Gtk", "4.0"), ("Adw", "1"), ("Gsk", "4.0"), ("Graphene", "1.0"), ("Gio", "2.0")):
    gi.require_version(n, v)
from gi.repository import Gtk, Adw, Gio, Graphene, GLib

F = Gtk.StateFlags
OUT = sys.argv[1] if len(sys.argv) > 1 else "docs/ui/looks/ref/linux"
ONLY = sys.argv[2] if len(sys.argv) > 2 else ""
ROWS = []  # (neper control id, file name, builder, state flags, note)
STATES = {"normal": F.NORMAL, "hover": F.PRELIGHT, "active": F.ACTIVE | F.PRELIGHT,
          "focus": F.FOCUSED | F.FOCUS_VISIBLE, "disabled": F.INSENSITIVE}


def reg(neper, name, build, flags=F.NORMAL, note=""):
    ROWS.append((neper, name, build, flags, note))


def states(neper, name, build, which=STATES):
    for s, fl in which.items():
        reg(neper, f"{name}-{s}", build, fl)


def kids(w):
    c = w.get_first_child()
    while c:
        yield c
        c = c.get_next_sibling()


def box(*items, vertical=True, spacing=6):
    b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL if vertical else Gtk.Orientation.HORIZONTAL, spacing=spacing)
    for k in items:
        b.append(k)
    return b


def css(w, *classes):
    for c in classes:
        w.add_css_class(c)
    return w


def sized(w, width=-1, height=-1):
    w.set_size_request(width, height)
    return w


def scrolled(child, w, h):
    sw = Gtk.ScrolledWindow()
    sw.set_child(child)
    sw.set_has_frame(True)
    return sized(sw, w, h)


# ---- label, button, toolbar button
reg("label", "label", lambda: Gtk.Label(label="Label text"))
reg("label", "label-dim", lambda: css(Gtk.Label(label="Secondary text"), "dim-label"))
reg("label", "label-heading", lambda: css(Gtk.Label(label="Heading"), "heading"))
for kind, cls in [("default", []), ("suggested", ["suggested-action"]), ("destructive", ["destructive-action"]),
                  ("flat", ["flat"]), ("pill", ["pill"])]:
    states("button", f"button-{kind}", lambda cls=cls: css(Gtk.Button(label="Button"), *cls))
states("button", "button-circular", lambda: css(Gtk.Button(icon_name="list-add-symbolic"), "circular"))
reg("button", "button-linked", lambda: css(box(*[Gtk.Button(label=t) for t in ("One", "Two", "Three")], vertical=False, spacing=0), "linked"))
states("toolbar_button", "button-icon", lambda: Gtk.Button(icon_name="edit-copy-symbolic"))
states("toolbar_button", "button-flat-icon", lambda: css(Gtk.Button(icon_name="edit-copy-symbolic"), "flat"))
reg("toolbar_button", "toggle-on", lambda: Gtk.ToggleButton(label="Toggle", active=True))
reg("toolbar_button", "toggle-off", lambda: Gtk.ToggleButton(label="Toggle"))

# ---- check, radio, switch
def check(active=False, inconsistent=False):
    c = Gtk.CheckButton(label="Check", active=active)
    c.set_inconsistent(inconsistent)
    return c


def radio(on):
    first = Gtk.CheckButton()
    r = Gtk.CheckButton(label="Radio", group=first)
    r.set_active(on)
    return r


for s, fl in STATES.items():
    reg("checkbox", f"check-off-{s}", check, fl)
    reg("checkbox", f"check-on-{s}", lambda: check(True), fl)
    reg("checkbox", f"check-mixed-{s}", lambda: check(inconsistent=True), fl)
    reg("radio", f"radio-off-{s}", lambda: radio(False), fl)
    reg("radio", f"radio-on-{s}", lambda: radio(True), fl)
    reg("checkbox", f"switch-off-{s}", Gtk.Switch, fl)
    reg("checkbox", f"switch-on-{s}", lambda: Gtk.Switch(active=True), fl)


def rgroup():
    a = Gtk.CheckButton(label="First", active=True)
    return box(a, Gtk.CheckButton(label="Second", group=a), Gtk.CheckButton(label="Third", group=a))


reg("radio_group", "radio-group", rgroup)
reg("group_box", "card", lambda: sized(css(box(Gtk.Label(label="Content", margin_top=24, margin_bottom=24)), "card"), 200, 80))


def frame():
    f = Gtk.Frame(label="Group")
    f.set_child(sized(Gtk.Label(label="Content"), 200, 60))
    return f


reg("group_box", "frame", frame)

# ---- entries and editors
for s, fl in STATES.items():
    reg("text_edit", f"entry-{s}", lambda: sized(Gtk.Entry(text="Some text"), 200), fl)
    reg("spin_edit", f"spin-{s}", lambda: sized(Gtk.SpinButton.new_with_range(0, 100, 1), 120), fl)
    reg("combo_box", f"dropdown-{s}", lambda: sized(Gtk.DropDown.new_from_strings(["First", "Second", "Third"]), 160), fl)
reg("text_edit", "entry-placeholder", lambda: sized(Gtk.Entry(placeholder_text="Placeholder"), 200))
for cls in ("error", "warning", "success"):
    reg("text_edit", f"entry-{cls}", lambda cls=cls: sized(css(Gtk.Entry(text=cls.title()), cls), 200))
reg("text_edit", "entry-password", lambda: sized(Gtk.PasswordEntry(show_peek_icon=True), 200))
reg("text_edit", "search-entry", lambda: sized(Gtk.SearchEntry(text="query"), 200))
reg("mask_edit", "entry-mask", lambda: sized(Gtk.Entry(text="(555) 010-1234"), 200))


def spin_v():
    s = Gtk.SpinButton.new_with_range(0, 100, 1)
    s.set_value(42)
    return css(s, "vertical")


reg("spin_edit", "spin-vertical", spin_v)
reg("image_combo_box", "dropdown-ellipsis", lambda: sized(Gtk.DropDown.new_from_strings(["A very long entry that is cut off", "B"]), 140))


def combo_entry():
    c = Gtk.ComboBoxText.new_with_entry()
    c.append_text("One")
    c.append_text("Two")
    c.set_active(0)
    return c


reg("combo_box", "combo-entry", combo_entry)


def datebtn():
    mb = Gtk.MenuButton(label="2026-10-16")
    mb.set_popover(Gtk.Popover(child=Gtk.Calendar()))
    return mb


reg("date_edit", "date-button", datebtn)
reg("date_edit", "calendar", Gtk.Calendar)


def memo():
    tv = Gtk.TextView(left_margin=8, top_margin=8)
    tv.get_buffer().set_text("Multi-line\ntext area")
    return scrolled(tv, 220, 100)


reg("memo", "textview", memo)
reg("button_edit", "entry-with-button", lambda: css(box(Gtk.Entry(text="Value"), Gtk.Button(icon_name="folder-open-symbolic"), vertical=False, spacing=0), "linked"))
reg("token_edit", "tokens", lambda: box(*[css(Gtk.Button(label=t), "pill") for t in ("alpha", "beta", "gamma")], vertical=False))

# ---- lists
def cklist():
    lb = css(Gtk.ListBox(), "boxed-list")
    for i, t in enumerate(("One", "Two", "Three")):
        r = Gtk.ListBoxRow()
        r.set_child(box(Gtk.CheckButton(active=i == 1), Gtk.Label(label=t), vertical=False, margin_top=8) if False else box(Gtk.CheckButton(active=i == 1), Gtk.Label(label=t), vertical=False))
        lb.append(r)
    return sized(lb, 220)


reg("check_list_box", "check-list", cklist)


def listbox(sel=None, hover=None):
    def b():
        lb = css(Gtk.ListBox(), "boxed-list")
        for t in ("Alpha", "Beta", "Gamma", "Delta"):
            r = Gtk.ListBoxRow()
            r.set_child(Gtk.Label(label=t, xalign=0, margin_top=12, margin_bottom=12, margin_start=12))
            lb.append(r)
        if sel is not None:
            lb.select_row(lb.get_row_at_index(sel))
        if hover is not None:
            lb.get_row_at_index(hover).set_state_flags(F.PRELIGHT, False)
        return sized(lb, 220)
    return b


reg("list_box", "listbox", listbox())
reg("list_box", "listbox-selected", listbox(sel=1))
reg("list_box", "listbox-hover", listbox(hover=2))


def action_rows():
    lb = css(Gtk.ListBox(), "boxed-list")
    lb.set_selection_mode(Gtk.SelectionMode.NONE)
    for t, s in (("Name", "Value one"), ("Version", "1.5.0"), ("Path", "/usr/lib")):
        lb.append(Adw.ActionRow(title=t, subtitle=s))
    lb.append(Adw.SwitchRow(title="Enabled", active=True))
    lb.append(Adw.EntryRow(title="Entry"))
    lb.append(Adw.ComboRow(title="Choice", model=Gtk.StringList.new(["A", "B"])))
    return sized(lb, 320)


reg("vertical_grid", "action-rows", action_rows)


def pref_group():
    g = Adw.PreferencesGroup(title="Group", description="Description")
    for t, s in (("Name", "Value"), ("Version", "1.5.0")):
        g.add(Adw.ActionRow(title=t, subtitle=s))
    return sized(g, 320)


reg("vertical_grid", "preferences-group", pref_group)


def tree(selected=False):
    def b():
        st = Gtk.TreeStore(str, str)
        for i in range(3):
            p = st.append(None, [f"Parent {i}", str(i)])
            for j in range(2):
                st.append(p, [f"Child {j}", f"{i}.{j}"])
        tv = Gtk.TreeView(model=st)
        for n, c in (("Name", 0), ("Value", 1)):
            col = Gtk.TreeViewColumn(n, Gtk.CellRendererText(), text=c)
            col.set_min_width(110)
            tv.append_column(col)
        tv.expand_all()
        if selected:
            tv.get_selection().select_path(Gtk.TreePath.new_from_string("0:1"))
        return scrolled(tv, 260, 190)
    return b


reg("tree_list", "treeview", tree())
reg("tree_list", "treeview-selected", tree(True))


def colview():
    sel = Gtk.SingleSelection(model=Gtk.StringList.new([f"Item {i}" for i in range(6)]))
    sel.set_selected(1)
    cv = Gtk.ColumnView(model=sel)
    for t in ("Name", "Detail"):
        f = Gtk.SignalListItemFactory()
        f.connect("setup", lambda _f, li: li.set_child(Gtk.Label(xalign=0)))
        f.connect("bind", lambda _f, li, t=t: li.get_child().set_text(li.get_item().get_string() if t == "Name" else "detail"))
        cv.append_column(Gtk.ColumnViewColumn(title=t, factory=f))
    return scrolled(cv, 280, 200)


reg("data_grid", "columnview", colview)

# ---- progress, scale, scrollbar, spinner
for v in (0, 40, 100):
    reg("progress_bar", f"progress-{v}", lambda v=v: sized(Gtk.ProgressBar(fraction=v / 100), 200))
reg("progress_bar", "progress-osd", lambda: sized(css(Gtk.ProgressBar(fraction=.6), "osd"), 200))
reg("progress_bar", "levelbar", lambda: sized(Gtk.LevelBar.new_for_interval(0, 10), 200))
reg("progress_bar", "spinner", lambda: sized(Gtk.Spinner(spinning=True), 32, 32))


def scale():
    s = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
    s.set_value(40)
    return sized(s, 200)


states("progress_bar", "scale", scale)


def scale_marks():
    s = scale()
    s.add_mark(0, Gtk.PositionType.BOTTOM, "0")
    s.add_mark(100, Gtk.PositionType.BOTTOM, "100")
    return s


reg("progress_bar", "scale-marks", scale_marks)


def lone_sb(o):
    def b():
        a = Gtk.Adjustment(value=20, lower=0, upper=100, page_size=30)
        h = o == Gtk.Orientation.HORIZONTAL
        return sized(Gtk.Scrollbar(orientation=o, adjustment=a), 200 if h else -1, -1 if h else 160)
    return b


for s, fl in {"normal": F.NORMAL, "hover": F.PRELIGHT, "disabled": F.INSENSITIVE}.items():
    reg("scroll_bar", f"scrollbar-h-{s}", lone_sb(Gtk.Orientation.HORIZONTAL), fl)
    reg("scroll_bar", f"scrollbar-v-{s}", lone_sb(Gtk.Orientation.VERTICAL), fl)


def scrolled_bars(overlay):
    def b():
        sw = Gtk.ScrolledWindow(has_frame=True, overlay_scrolling=overlay)
        sw.set_policy(Gtk.PolicyType.ALWAYS, Gtk.PolicyType.ALWAYS)
        sw.set_child(sized(Gtk.Label(label="x"), 600, 600))
        return sized(sw, 160, 120)
    return b


reg("scroll_bar", "scrolled-overlay", scrolled_bars(True))
reg("scroll_bar", "scrolled-classic", scrolled_bars(False))

# ---- tabs, splitter, status, toolbar, menus
def notebook(pos):
    def b():
        n = Gtk.Notebook(tab_pos=pos)
        for t in ("General", "Advanced", "About"):
            n.append_page(sized(Gtk.Label(label=t + " page"), 240, 90), Gtk.Label(label=t))
        n.set_current_page(1)
        return n
    return b


reg("page_control", "notebook-top", notebook(Gtk.PositionType.TOP))
reg("page_control", "notebook-left", notebook(Gtk.PositionType.LEFT))


def tabbar():
    v = Adw.TabView()
    for t in ("Tab one", "Tab two", "Tab three"):
        v.append(sized(Gtk.Label(label=t), 100, 40)).set_title(t)
    return box(Adw.TabBar(view=v, autohide=False), sized(v, 380, 60), spacing=0)


reg("page_control", "adw-tabbar", tabbar)


def switcher():
    st = Adw.ViewStack()
    st.add_titled(Gtk.Label(label="A"), "a", "General")
    st.add_titled(Gtk.Label(label="B"), "b", "Advanced")
    return box(Adw.ViewSwitcher(stack=st, policy=Adw.ViewSwitcherPolicy.WIDE), st)


reg("page_control", "adw-viewswitcher", switcher)
reg("splitter", "separator-h", lambda: sized(Gtk.Separator(), 200, 4))
reg("splitter", "separator-v", lambda: sized(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), 4, 60))


def paned(wide=False):
    def b():
        p = Gtk.Paned()
        p.set_start_child(sized(Gtk.Label(label="Left"), 100, 80))
        p.set_end_child(sized(Gtk.Label(label="Right"), 100, 80))
        return css(p, "wide") if wide else p
    return b


reg("splitter", "paned", paned())
reg("splitter", "paned-wide", paned(True))


def headerbar(sub=""):
    def b():
        h = Adw.HeaderBar(title_widget=Adw.WindowTitle(title="Title", subtitle=sub))
        h.pack_start(Gtk.Button(icon_name="list-add-symbolic"))
        h.pack_end(Gtk.Button(icon_name="open-menu-symbolic"))
        return sized(h, 420)
    return b


reg("toolbar_button", "headerbar", headerbar())
reg("status_bar", "headerbar-subtitle", headerbar("Subtitle"))


def actionbar():
    ab = Gtk.ActionBar()
    ab.pack_start(Gtk.Label(label="Status text"))
    ab.pack_end(Gtk.Label(label="Ln 1, Col 1"))
    return sized(ab, 360)


reg("status_bar", "actionbar", actionbar)


def toolbar():
    names = ("document-new-symbolic", "document-open-symbolic", "document-save-symbolic", None, "edit-cut-symbolic", "edit-copy-symbolic")
    return css(box(*[css(Gtk.Button(icon_name=n), "flat") if n else Gtk.Separator(orientation=Gtk.Orientation.VERTICAL) for n in names], vertical=False), "toolbar")


reg("toolbar_button", "toolbar", toolbar)


def menu_model():
    m = Gio.Menu()
    s1 = Gio.Menu()
    for t in ("New", "Open", "Save"):
        s1.append(t, "app.x")
    m.append_section(None, s1)
    s2 = Gio.Menu()
    s2.append("Preferences", "app.x")
    sub = Gio.Menu()
    sub.append("Sub item", "app.x")
    s2.append_submenu("Submenu", sub)
    m.append_section(None, s2)
    s3 = Gio.Menu()
    s3.append("Quit", "app.x")
    m.append_section(None, s3)
    return m


def menubar():
    m = Gio.Menu()
    for top in ("File", "Edit", "Help"):
        sub = Gio.Menu()
        sub.append("Item", "app.x")
        m.append_submenu(top, sub)
    return Gtk.PopoverMenuBar.new_from_model(m)


reg("menu_bar", "menubar", menubar)


def menu_button():
    mb = Gtk.MenuButton(label="Menu")
    mb.set_popover(Gtk.PopoverMenu.new_from_model(menu_model()))
    mb._open = True
    return mb


reg("popup_menu", "popover-menu-open", menu_button, note="popover surface captured on its own")


def dd_open():
    d = Gtk.DropDown.new_from_strings(["First", "Second", "Third"])
    d._open = True
    return sized(d, 160)


reg("combo_box", "dropdown-open", dd_open, note="popover surface captured on its own")


def tooltip():
    # a real tooltip is its own surface; this reproduces the node tree: tooltip.background > box > label
    b = box(Gtk.Label(label="Tooltip text"), spacing=0)
    css(b, "tooltip", "background")
    return b


reg("hint", "tooltip", tooltip, note="approximation: the .tooltip CSS node, not the real tooltip surface")
reg("dialog", "alert-dialog", lambda: None, note="Adw.AlertDialog over its parent window")


# ---- rendering
def settle(n=6):
    ctx = GLib.MainContext.default()
    for _ in range(n):
        end = GLib.get_monotonic_time() + 60000
        while GLib.get_monotonic_time() < end:
            while ctx.pending():
                ctx.iteration(False)


def to_texture(widget, scale, bg=None):
    w, h = widget.get_width(), widget.get_height()
    sn = Gtk.Snapshot()
    sn.scale(scale, scale)
    if bg:
        sn.append_color(bg, Graphene.Rect().init(0, 0, w, h))
    Gtk.WidgetPaintable.new(widget).snapshot(sn, w, h)
    return widget.get_native().get_renderer().render_texture(sn.to_node(), Graphene.Rect().init(0, 0, w * scale, h * scale))


def apply_flags(wd, flags):
    wd.set_state_flags(flags, False)
    for c in kids(wd):  # composite widgets draw state on inner nodes
        c.set_state_flags(F(int(flags) & ~int(F.INSENSITIVE)), False)
    if flags & F.INSENSITIVE:
        wd.set_sensitive(False)


def popover_texture(wd, scale):
    pop = wd.get_popover() if isinstance(wd, Gtk.MenuButton) else next(c for c in kids(wd) if isinstance(c, Gtk.Popover))
    pop.popup()
    settle(10)
    nat = pop.get_native()
    tex = None
    if nat is not None and not isinstance(nat, Gtk.Window):
        tex = to_texture(nat, scale)
    pop.popdown()
    settle(3)
    return tex


def main():
    Adw.init()
    Gtk.Settings.get_default().set_property("gtk-font-name", "Cantarell 11")  # what GNOME 45 to 47 ships
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
            if ONLY and ONLY not in name:
                continue
            try:
                if name == "alert-dialog":
                    win.set_content(Gtk.Box())
                    settle()
                    d = Adw.AlertDialog(heading="Delete file?", body="This cannot be undone.")
                    d.add_response("cancel", "Cancel")
                    d.add_response("delete", "Delete")
                    d.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                    d.set_default_response("cancel")
                    d.present(win)
                    settle(12)
                    texs = {s: to_texture(win, s) for s in (1, 2)}
                    d.force_close()
                    settle(3)
                else:
                    wd = build()
                    pad = Gtk.Box(margin_top=12, margin_bottom=12, margin_start=12, margin_end=12, halign=Gtk.Align.START, valign=Gtk.Align.START)
                    pad.append(wd)
                    win.set_content(pad)
                    settle()
                    if flags != F.NORMAL:
                        apply_flags(wd, flags)
                        settle(20 if flags & F.FOCUSED else 3)  # the 200 ms outline transition must finish (a 3 tick capture is a thinner, blended ring)
                    if getattr(wd, "_open", False):
                        texs = {s: popover_texture(wd, s) for s in (1, 2)}
                    else:
                        texs = {s: to_texture(pad, s, bg) for s in (1, 2)}
                for s, tex in texs.items():
                    if tex is None:
                        raise RuntimeError("no texture")
                    tex.save_to_png(f"{OUT}/{scheme}/{name}@{s}x.png")
                manifest.append((scheme, neper, name, f"{scheme}/{name}@1x.png", f"{scheme}/{name}@2x.png",
                                 texs[1].get_width(), texs[1].get_height(), note))
            except Exception as e:  # keep going; report at the end
                print("FAIL", scheme, name, e, file=sys.stderr)
        win.destroy()
    with open(f"{OUT}/manifest.csv", "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["scheme", "neper_control", "name", "png_1x", "png_2x", "w_1x", "h_1x", "note"])
        wr.writerows(manifest)
    print(len(manifest), "entries (1x+2x each) written to", OUT)


if __name__ == "__main__":
    main()
