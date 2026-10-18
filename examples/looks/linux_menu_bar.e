// The Linux look's menu bar against the real GTK 4.14 / libadwaita 1.5 GtkPopoverMenuBar: File, Edit and Help at rest and with
// Edit selected (hovered or its menu open), docs/ui/looks/linux[-dark]/menu_bar.png (reference: scripts/linux_cmp_l3.py, the
// selected state from scripts/linux/gallery_l3.py). Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 3usize)
    if actions_error != ok { ret (0usize, actions_error) }
    let (items, items_error) = mem.alloc[navigation.BarCommand](a, 1usize)
    if items_error != ok { ret (0usize, items_error) }
    var item: navigation.BarCommand = zero
    item.label = "Item"
    item.enabled = true
    items[0usize] = item
    let (menus, menus_error) = mem.alloc[navigation.BarMenu](a, 3usize)
    if menus_error != ok { ret (0usize, menus_error) }
    let titles = [3]str{ "File", "Edit", "Help" }
    var i = 0usize
    while i < 3usize {
        actions[i] = widget.Submit { ctx: zero, invoke: noop_submit }
        menus[i] = navigation.BarMenu { label: titles[i], commands: items[0usize..1usize] }
        i += 1usize
    }
    let captions = [2]str{ "rest", "Edit selected" }
    var k = 0usize
    while k < 2usize {
        // the second cell opens nothing (a modal menu renders one per process); the pointer's hover gives the selected look
        let (bar, bar_error) = navigation.menu_bar_of(a, u64(10000usize * (k + 1usize)), t, "Main menu", menus[0usize..3usize], 99usize, actions[0usize..3usize])
        if bar_error != ok { ret (0usize, bar_error) }
        var drive: looks.Drive = .None
        if k == 1usize { drive = .Hover }
        let held = widget.positioned(0u64, 40.0, 16.0, control.sized_style(129.0, 28.0), control.widget_one_of(a, bar))
        cells[k] = looks.Cell { caption: captions[k], node: widget.stack(0u64, control.sized_style(210.0, 60.0), control.widget_one_of(a, held)), drive: drive }
        k += 1usize
    }
    // aim the pointer at Edit: the cell centre is x 105, Edit's centre 40 + 61 = 101
    looks.aim(1usize, -4.0, 0.0)
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "menu_bar", cells: 2usize, columns: 2usize, cell_w: 210.0, cell_h: 60.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
