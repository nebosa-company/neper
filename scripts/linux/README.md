# Linux (Adwaita) reference gallery

Renders real GTK4 / libadwaita widgets to PNG with no display and no desktop interaction:
Xvfb provides an X11 display, GSK's Cairo renderer turns a `Gtk.WidgetPaintable` snapshot into a
`Gdk.Texture`, and `save_to_png` writes it. Light and dark come from
`Adw.StyleManager.set_color_scheme(FORCE_LIGHT / FORCE_DARK)`.

## Setup (WSL Ubuntu 24.04, once)

    sudo apt-get install -y --no-install-recommends python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 xvfb fonts-cantarell adwaita-icon-theme

## Run (from the repo root, inside WSL)

    sh scripts/linux/run.sh                                  # writes docs/ui/looks/ref/linux
    sh scripts/linux/run.sh /tmp/out button                  # only names containing "button"
    xvfb-run -a python3 scripts/linux/tokens.py              # named colours as a markdown table

Output: `docs/ui/looks/ref/linux/{light,dark}/<control>-<state>@{1x,2x}.png`, `manifest.csv`
(scheme, neper control id, name, files, 1x size, note) and `adwaita-tokens.md`.

## Limits

- 2x is a vector re-render at scale 2 (crisp), not `GDK_SCALE=2`, so it shows 2x layout of the
  same logical sizes.
- Hover / active / focus are forced with `set_state_flags`; composite widgets get the flags on their
  inner nodes too. Pointer-only effects (overlay scrollbar growth, tooltip delays) are not driven.
- Popovers (menu, drop down list) are captured from their own surface, so their corners are
  transparent (shown black in some viewers). The tooltip is the `.tooltip` CSS node, not a real
  tooltip surface. The dialog is the whole window with an `AdwAlertDialog` over it.
- The font is Cantarell 11 (libadwaita 1.5); newer libadwaita uses Adwaita Sans.

## Neper control mapping (docs/ui/looks/status.json ids)

label: GtkLabel; button: GtkButton (default, suggested, destructive, flat, pill, circular, linked);
checkbox / radio / radio_group: GtkCheckButton, GtkSwitch; text_edit: GtkEntry (+error/warning/success);
spin_edit: GtkSpinButton; combo_box / image_combo_box: GtkDropDown, GtkComboBoxText;
date_edit: MenuButton + GtkCalendar; mask_edit: GtkEntry; memo: GtkTextView; button_edit: linked
entry + button; token_edit: pill buttons (no native token entry in GTK); check_list_box: ListBox with
check buttons; progress_bar: GtkProgressBar, LevelBar, Scale, Spinner; group_box: card, GtkFrame;
page_control: GtkNotebook, AdwTabBar, AdwViewSwitcher; splitter: GtkPaned, GtkSeparator;
status_bar: AdwHeaderBar subtitle, GtkActionBar; toolbar_button: button, toggle, AdwHeaderBar,
`.toolbar`; menu_bar: GtkPopoverMenuBar; popup_menu: GtkPopoverMenu; hint: tooltip;
scroll_bar: GtkScrollbar and overlay / classic ScrolledWindow; list_box: boxed GtkListBox;
tree_list: GtkTreeView; vertical_grid: AdwActionRow / AdwPreferencesGroup; data_grid: GtkColumnView;
dialog: AdwAlertDialog.
