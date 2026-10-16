// The Cupertino (iOS) alert: docs/ui/looks/cupertino/dialog.png (and cupertino-dark). The alert card (overlay.
// cupertino_alert_card, the face the open dialog draws over its scrim) with two buttons side by side, a default and a
// destructive button, three stacked, one button; and with a button pressed. The open overlay dialog itself is the
// second sheet (dialog_open): a modal overlay, so it holds one cell (run with an argument).

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.overlay
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn message(a: *mem.Arena, t: *const control.Theme, words: str) -> (widget.Node, err) {
    var options = control.text_options()
    options.role = .BodyMedium
    options.size = 13.0
    options.align = .Center
    let (node, node_error) = control.colored_text(a, 0u64, words, t, options, style.color(t.tokens, .Text))
    ret (node, node_error)
}

fn buttons_of(a: *mem.Arena, action: widget.Submit, count: usize, destructive: bool) -> ([]overlay.DialogButton, err) {
    let (list, list_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = overlay.DialogButton { label: "Cancel", action: action, kind: .Cancel }
    list[1usize] = overlay.DialogButton { label: "OK", action: action, kind: .Default }
    if destructive { list[1usize] = overlay.DialogButton { label: "Delete", action: action, kind: .Destructive } }
    list[2usize] = overlay.DialogButton { label: "Later", action: action, kind: .Plain }
    if count == 3usize {
        list[0usize] = overlay.DialogButton { label: "Save", action: action, kind: .Default }
        list[1usize] = overlay.DialogButton { label: "Don't Save", action: action, kind: .Destructive }
        list[2usize] = overlay.DialogButton { label: "Cancel", action: action, kind: .Cancel }
    }
    ret (list[0usize..count], ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let names = [5]str{ "two buttons", "destructive", "three stacked", "one button", "pressed (stacked)" }
    var i = 0usize
    while i < 5usize {
        var count = 2usize
        var destructive = false
        var title = "Allow \"Maps\" to use your location?"
        var words = "Your location is used to show nearby results."
        if i == 1usize {
            destructive = true
            title = "Delete Deck?"
            words = "This deck and its notes will be removed."
        }
        if i == 2usize || i == 4usize {
            count = 3usize
            title = "Save changes?"
            words = "Your changes will be lost if you do not save."
        }
        if i == 3usize {
            count = 1usize
            title = "Update Complete"
            words = "Your library is up to date."
        }
        let (buttons, buttons_error) = buttons_of(a, actions[0usize], count, destructive)
        if buttons_error != ok { ret (0usize, buttons_error) }
        if i == 3usize {
            buttons[0usize] = overlay.DialogButton { label: "OK", action: actions[0usize], kind: .Default }
        }
        let (words_node, words_error) = message(a, t, words)
        if words_error != ok { ret (0usize, words_error) }
        let (card, card_error) = overlay.cupertino_alert_card(a, u64((i + 1usize) * 100usize), t, title, words_node, buttons)
        if card_error != ok { ret (0usize, card_error) }
        var drive: looks.Drive = .None
        if i == 4usize { drive = .Press }
        cells[i] = looks.Cell { caption: names[i], node: card, drive: drive }
        i += 1usize
    }
    ret (5usize, ok)
}

fn build_open(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let (buttons, buttons_error) = buttons_of(a, actions[0usize], 2usize, false)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let (node, node_error) = overlay.alert_dialog(a, 100u64, t, "Allow \"Maps\" to use your location?", "Your location is used to show nearby results.", buttons, true)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "open alert over its scrim", node: node, drive: .None }
    ret (1usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize {
        let open = looks.Sheet { name: "dialog_open", cells: 1usize, columns: 1usize, cell_w: 380.0, cell_h: 240.0, ctx: zero, build: build_open }
        ret looks.run_cupertino(a, &open)
    }
    let sheet = looks.Sheet { name: "dialog", cells: 5usize, columns: 3usize, cell_w: 290.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
