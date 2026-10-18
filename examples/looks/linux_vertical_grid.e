// The Linux look's vertical grid against the real GTK 4.14 / libadwaita 1.5 action rows and preferences group:
// docs/ui/looks/linux[-dark]/vertical_grid.png. Left: a boxed list of action rows (three with a subtitle, a switch row, an entry row, a
// combo row); right: an AdwPreferencesGroup (heading, description, two action rows). Run from the repository root; see
// docs/ui/looks-howto.md. The strict compare is scripts/linux_cmp_l4.py.

use e.mem
use e.ui.collection
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 6usize)
    if actions_error != ok { ret (0usize, actions_error) }
    var n = 0usize
    while n < 6usize {
        actions[n] = widget.Submit { ctx: zero, invoke: noop_submit }
        n += 1usize
    }
    let (rows, rows_error) = mem.alloc[collection.LinuxRow](a, 6usize)
    if rows_error != ok { ret (0usize, rows_error) }
    rows[0usize] = collection.LinuxRow { title: "Name", subtitle: "Value one", kind: 0u8, value: "" }
    rows[1usize] = collection.LinuxRow { title: "Version", subtitle: "1.5.0", kind: 0u8, value: "" }
    rows[2usize] = collection.LinuxRow { title: "Path", subtitle: "/usr/lib", kind: 0u8, value: "" }
    rows[3usize] = collection.LinuxRow { title: "Enabled", subtitle: "", kind: 1u8, value: "" }
    rows[4usize] = collection.LinuxRow { title: "Entry", subtitle: "", kind: 3u8, value: "" }
    rows[5usize] = collection.LinuxRow { title: "Choice", subtitle: "", kind: 4u8, value: "A" }
    let (action_rows, action_error) = collection.linux_rows(a, 100u64, t, "", "", rows[0usize..6usize], actions[0usize..6usize], 320.0)
    if action_error != ok { ret (0usize, action_error) }
    let (group_rows, group_rows_error) = mem.alloc[collection.LinuxRow](a, 2usize)
    if group_rows_error != ok { ret (0usize, group_rows_error) }
    group_rows[0usize] = collection.LinuxRow { title: "Name", subtitle: "Value", kind: 0u8, value: "" }
    group_rows[1usize] = collection.LinuxRow { title: "Version", subtitle: "1.5.0", kind: 0u8, value: "" }
    let (group, group_error) = collection.linux_rows(a, 200u64, t, "Group", "Description", group_rows[0usize..2usize], actions[0usize..2usize], 320.0)
    if group_error != ok { ret (0usize, group_error) }
    cells[0usize] = looks.Cell { caption: "action rows", node: action_rows, drive: .None }
    cells[1usize] = looks.Cell { caption: "preferences group", node: group, drive: .None }
    ret (2usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "vertical_grid", cells: 2usize, columns: 2usize, cell_w: 340.0, cell_h: 349.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
