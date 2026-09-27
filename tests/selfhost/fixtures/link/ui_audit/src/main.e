// `e.ui.audit` (D1601) over two pages. A clean one -- a named field and a button --
// gives no finding. A faulty one gives each kind a page can show without fonts:
// two unnamed 16 x 16 buttons side by side (name, and target: too close for the
// spacing exception), a pressable group no Tab can reach (role, name, reach), and
// a button past the surface's bottom, which Tab reaches but cannot bring into view
// (focus obscured). No fonts: the contrast check measures drawn text, and there
// is none.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.accessibility
use e.ui.audit
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

type World = struct { theme: control.Theme, name: [16]u8, faulty: bool, storage: []u8, frame: mem.Arena }

fn on_name(ctx: *void, value: str) -> err { ret ok }
fn on_press(ctx: *void) -> err { ret ok }
fn on_button(ctx: *void, event: input.Event) -> err { ret ok }

fn one(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 1usize)
    if nodes_error != ok { ret zero }
    nodes[0usize] = node
    ret nodes[0usize..1usize]
}

fn tiny(a: *mem.Arena, key: widget.Key, w: *World) -> widget.Node {
    ret widget.button(key, widget.Button { action: widget.Action { ctx: mem.cast[*void](w), invoke: on_button }, enabled: true }, control.sized_style(16.0, 16.0), zero)
}

fn build(ctx: *void, context: *widget.BuildContext) -> (widget.Node, err) {
    let w = mem.cast[*World](ctx)
    w.theme.runtime = context.runtime
    w.frame = mem.arena_from(w.storage)
    let a = &w.frame
    let t = &w.theme
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    var n = 0usize
    if !w.faulty {
        let (field, field_error) = control.text_field(a, 10u64, t, "Name", w.name[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_name }, zero, control.field_options())
        if field_error != ok { ret (zero, field_error) }
        items[n] = field
        n += 1usize
        let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 0usize)
        if fonts_error != ok { ret (zero, fonts_error) }
        let words = widget.text(0u64, widget.Text { value: "Save", style: layout.Style { fonts: fonts, language: "", line_height: 16.0 }, color: paint.rgba(0.0, 0.0, 0.0, 1.0), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
        items[n] = widget.button(20u64, widget.Button { action: widget.Action { ctx: ctx, invoke: on_button }, enabled: true }, control.sized_style(96.0, 40.0), one(a, words))
        n += 1usize
    } else {
        let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
        if pair_error != ok { ret (zero, pair_error) }
        pair[0usize] = tiny(a, 30u64, w)
        pair[1usize] = tiny(a, 31u64, w)
        items[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), pair[0usize..2usize])
        n += 1usize
        // Pressable to a screen reader, a group, and no focus to Tab to.
        var ghost: widget.Semantics = zero
        ghost.role = 2u8
        ghost.actions = accessibility.ACTION_PRESS
        items[n] = widget.semantics(40u64, ghost, style.defaults(), one(a, widget.box(0u64, control.sized_style(80.0, 32.0), zero)))
        n += 1usize
        // Placed past the bottom, with nothing to scroll it into view.
        let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 0usize)
        if fonts_error != ok { ret (zero, fonts_error) }
        let words = widget.text(0u64, widget.Text { value: "Far", style: layout.Style { fonts: fonts, language: "", line_height: 16.0 }, color: paint.rgba(0.0, 0.0, 0.0, 1.0), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
        let far = widget.button(50u64, widget.Button { action: widget.Action { ctx: ctx, invoke: on_button }, enabled: true }, control.sized_style(96.0, 40.0), one(a, words))
        items[n] = widget.stack(0u64, control.sized_style(96.0, 40.0), one(a, widget.positioned(0u64, 0.0, 500.0, style.defaults(), one(a, far))))
        n += 1usize
    }
    var column = style.defaults()
    column.width = style.Length { Px: 400.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..n]), ok)
}

fn counted(report: []const audit.Finding, count: usize, check: audit.Check) -> usize {
    var found = 0usize
    var i = 0usize
    while i < count {
        if report[i].check == check { found += 1usize }
        i += 1usize
    }
    ret found
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (tokens, tokens_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if tokens_error != ok { os.exit(5i32) }
    tokens[0usize] = style.reference(.Light)
    let (storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(6i32) }
    let (worlds, worlds_error) = mem.alloc[World](a, 1usize)
    if worlds_error != ok { os.exit(7i32) }
    var world: World = zero
    world.theme = control.Theme { tokens: &tokens[0usize], fonts: fonts, language: "", runtime: zero }
    world.storage = storage
    worlds[0usize] = world
    let w = &worlds[0usize]
    let page = audit.Page { ctx: mem.cast[*void](w), build: build }
    var o = audit.options()
    o.width = 400u32
    o.height = 300u32
    o.frame_bytes = 4194304usize
    o.max_stops = 32usize
    let (findings, findings_error) = mem.alloc[audit.Finding](a, 32usize)
    if findings_error != ok { os.exit(8i32) }
    let limits = widget.Limits { max_elements: 256usize, max_states: 32usize, state_bytes: 1024usize, state_classes: 4u16, max_depth: 24u16, max_commands: 1024usize }
    // The clean page: nothing to report.
    let (clean_runtime, clean_error) = widget.runtime(a, &renderer, limits)
    if clean_error != ok { os.exit(9i32) }
    var clean = clean_runtime
    let (clean_report, clean_run_error) = audit.run(a, &clean, page, o, findings)
    if clean_run_error != ok { os.exit(10i32) }
    if clean_report.count != 0usize || clean_report.stops != 2usize || clean_report.nodes == 0usize { os.exit(11i32) }
    // The faulty page: each kind it holds.
    w.faulty = true
    let (faulty_runtime, faulty_error) = widget.runtime(a, &renderer, limits)
    if faulty_error != ok { os.exit(12i32) }
    var faulty = faulty_runtime
    let (report, run_error) = audit.run(a, &faulty, page, o, findings)
    if run_error != ok { os.exit(13i32) }
    if counted(findings, report.count, .Name) < 3usize { os.exit(14i32) }
    if counted(findings, report.count, .Role) != 1usize { os.exit(15i32) }
    if counted(findings, report.count, .Target) != 2usize { os.exit(16i32) }
    if counted(findings, report.count, .Reach) != 1usize { os.exit(17i32) }
    if counted(findings, report.count, .FocusObscured) != 1usize { os.exit(18i32) }
    if counted(findings, report.count, .Contrast) != 0usize || counted(findings, report.count, .FocusLost) != 0usize || counted(findings, report.count, .FocusTrap) != 0usize { os.exit(19i32) }
    if report.dropped != 0usize || !same_text(audit.check_name(.FocusObscured), "focus-obscured") { os.exit(20i32) }
    try io.print("ui audit ok\n")
    ret ok
}

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}
