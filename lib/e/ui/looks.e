// Looks: the harness behind docs/ui/looks. One small app per control builds that control in
// every state (`Cell`s) and hands them to `run_all`, which renders the sheet offscreen on the
// CPU backend, once per look (Neper, Windows) and per scale (1.0, 1.5), into
// docs/ui/looks/<look>/<name>[@1.5x].png, and, when the v3 reference capture
// docs/ui/looks/ref/windows/<name>[@1.5x].png exists, a side-by-side
// docs/ui/looks/windows/<name>-vs-ref[@1.5x].png (reference left, ours right).
//
// No window, mouse or keyboard is involved. The interaction states (hover, pressed, focused) are
// produced by driving the page's own runtime with synthetic events, one frame per driven cell,
// and cropping that cell out of the frame, because a control reads what the pointer and the
// focus are doing to it from the runtime when it is built.

use e.fmt.png
use e.fs
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.io
use e.mem
use e.str as strs
use e.text.shape
use e.time
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

// The four looks. Cupertino and Material have no tokens of their own yet: `theme_for` answers
// the Neper tokens carrying their profile, and `run_all` does not render them.
type Look = enum u8 { Neper, Windows, Cupertino, Material, WindowsDark, CupertinoDark }
// How a cell's state is produced: None (at rest, or whatever the build made of it, for example
// disabled), Hover (the pointer over it), Press (the primary button held on it), Focus (keyboard
// focus, ring visible), Select (focus, then Ctrl+A: an edit's whole text selected).
type Drive = enum u8 { None, Hover, Press, Focus, Select }
type Cell = struct { caption: str, node: widget.Node, drive: Drive }
// Fills `cells` (up to its length) with the control in its states and answers how many; called
// again for every driven cell, so it must build the same keys every time. Control keys must be
// unique in the sheet and non-zero.
type Build = fn(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []Cell) -> (usize, err)
// A sheet: `name` is the file stem (the control), `columns` cells per row, each cell a box of
// `cell_w` x `cell_h` logical px with the control centred in it and its caption above.
type Sheet = struct { name: str, cells: usize, columns: usize, cell_w: f32, cell_h: f32, ctx: *void, build: Build }
type Rig = struct { a: *mem.Arena, renderer: scene.Renderer, runtime: widget.Runtime, harness: testing.Harness, tokens: style.ThemeTokens, fonts: []shape.Font, frame_storage: []u8, frame: mem.Arena, width: f32, height: f32, scale: f32 }
error Failed

fn margin() -> f32 { ret 12.0 }
fn spacing() -> f32 { ret 10.0 }
fn caption_h() -> f32 { ret 16.0 }
fn out_root() -> str { ret "docs/ui/looks" }
fn segoe_path() -> str { ret "C:/Windows/Fonts/segoeui.ttf" }
fn tahoma_path() -> str { ret "C:/Windows/Fonts/tahoma.ttf" }
// Segoe UI Bold (font id 9), last in the chain: only a control that asks for weight 700 reaches it.
fn segoe_bold_path() -> str { ret "C:/Windows/Fonts/segoeuib.ttf" }
// Tahoma Bold (font id 10), last: v3 draws bold labels, captions, the Options pages' header title and the bars' group headers in it.
fn tahoma_bold_path() -> str { ret "C:/Windows/Fonts/tahomabd.ttf" }

// The tokens of a look, Light palette. Cupertino and Material are planned: the Neper tokens
// with the matching profile, so a control that branches on it can start to.
fn theme_for(look: Look) -> style.ThemeTokens {
    if look == .Windows { ret style.windows(.Light) }
    if look == .WindowsDark { ret style.windows(.Dark) }
    if look == .Cupertino { ret style.cupertino(.Light) }
    if look == .CupertinoDark { ret style.cupertino(.Dark) }
    var t = style.reference(.Light)
    if look == .Material { t.profile = .MaterialLike }
    ret t
}

fn look_dir(look: Look) -> str {
    if look == .Windows { ret "windows" }
    if look == .WindowsDark { ret "windows-dark" }
    if look == .Cupertino { ret "cupertino" }
    if look == .CupertinoDark { ret "cupertino-dark" }
    if look == .Material { ret "material" }
    ret "neper"
}

// A rig of `width` x `height` logical px at `scale`: the CPU gpu backend, the renderer, Segoe UI
// (font id 7, first in the theme's fallback chain) and Tahoma (id 8), a runtime, the harness and
// a frame arena. The Neper tokens until `set_look`. The rig lives in `a`.
fn open(a: *mem.Arena, width: f32, height: f32, scale: f32) -> (*Rig, err) {
    let (rigs, rig_error) = mem.alloc[Rig](a, 1usize)
    if rig_error != ok { ret (zero, rig_error) }
    let rig = &rigs[0usize]
    rig.a = a
    rig.width = width
    rig.height = height
    rig.scale = scale
    let (segoe_bytes, segoe_error) = fs.read_file(a, segoe_path(), 16777216usize)
    if segoe_error != ok { ret (rig, segoe_error) }
    let (tahoma_bytes, tahoma_error) = fs.read_file(a, tahoma_path(), 16777216usize)
    if tahoma_error != ok { ret (rig, tahoma_error) }
    let (bold_bytes, bold_error) = fs.read_file(a, segoe_bold_path(), 16777216usize)
    if bold_error != ok { ret (rig, bold_error) }
    let (tahoma_bold_bytes, tahoma_bold_error) = fs.read_file(a, tahoma_bold_path(), 16777216usize)
    if tahoma_bold_error != ok { ret (rig, tahoma_bold_error) }
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret (rig, device_error) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (rig, queue_error) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 64u32)
    if renderer_error != ok { ret (rig, renderer_error) }
    rig.renderer = r
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 4usize)
    if fonts_error != ok { ret (rig, fonts_error) }
    fonts[0usize] = shape.Font { id: 7u32, data: segoe_bytes, face_index: 0u32 }
    fonts[1usize] = shape.Font { id: 8u32, data: tahoma_bytes, face_index: 0u32 }
    fonts[2usize] = shape.Font { id: 9u32, data: bold_bytes, face_index: 0u32 }
    fonts[3usize] = shape.Font { id: 10u32, data: tahoma_bold_bytes, face_index: 0u32 }
    try scene.register_font(&rig.renderer, fonts[0usize])
    try scene.register_font(&rig.renderer, fonts[1usize])
    try scene.register_font(&rig.renderer, fonts[2usize])
    try scene.register_font(&rig.renderer, fonts[3usize])
    rig.fonts = fonts[0usize..4usize]
    let (rt, runtime_error) = widget.runtime(a, &rig.renderer, widget.Limits { max_elements: 16384usize, max_states: 1024usize, state_bytes: 65536usize, state_classes: 8u16, max_depth: 48u16, max_commands: 49152usize })
    if runtime_error != ok { ret (rig, runtime_error) }
    rig.runtime = rt
    let physical_w = u32(width * scale + 0.5)
    let physical_h = u32(height * scale + 0.5)
    let (h, harness_error) = testing.harness(a, &rig.runtime, physical_w, physical_h, scale)
    if harness_error != ok { ret (rig, harness_error) }
    rig.harness = h
    let (storage, storage_error) = mem.alloc[u8](a, 33554432usize)
    if storage_error != ok { ret (rig, storage_error) }
    rig.frame_storage = storage
    rig.frame = mem.arena_from(storage)
    rig.tokens = theme_for(.Neper)
    ret (rig, ok)
}

fn set_look(rig: *Rig, look: Look) {
    rig.tokens = theme_for(look)
}

// The control theme of the rig: its tokens, fonts and runtime.
fn theme_of(rig: *Rig) -> control.Theme {
    ret control.Theme { tokens: &rig.tokens, fonts: rig.fonts, language: "", runtime: &rig.runtime }
}

// The frame arena, emptied: everything built for one pass lives in it.
fn begin(rig: *Rig) -> *mem.Arena {
    rig.frame = mem.arena_from(rig.frame_storage)
    ret &rig.frame
}

fn noop_cell() -> widget.Node {
    ret widget.spacer(0u64, 0.0)
}

fn size_style(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

fn rows_of(count: usize, columns: usize) -> usize {
    ret (count + columns - 1usize) / columns
}

// The logical size of a sheet.
fn sheet_width(s: *const Sheet) -> f32 {
    ret margin() * 2.0 + f32(s.columns) * s.cell_w + f32(s.columns - 1usize) * spacing()
}

fn sheet_height(s: *const Sheet) -> f32 {
    let rows = rows_of(s.cells, s.columns)
    ret margin() * 2.0 + f32(rows) * (caption_h() + 4.0 + s.cell_h) + f32(rows - 1usize) * spacing()
}

// The top-left of cell `i`'s box, in logical px.
fn cell_origin(s: *const Sheet, i: usize) -> geometry.Point {
    let column = i % s.columns
    let row = i / s.columns
    ret geometry.Point { x: margin() + f32(column) * (s.cell_w + spacing()), y: margin() + f32(row) * (caption_h() + 4.0 + s.cell_h + spacing()) + caption_h() + 4.0 }
}

// Lays `cells` into a labelled grid: rows of `columns`, each cell a caption above a
// `cell_w` x `cell_h` box that centres its control, on the theme's background.
fn sheet(a: *mem.Arena, t: *const control.Theme, cells: []const Cell, columns: usize, cell_w: f32, cell_h: f32) -> (widget.Node, err) {
    var page = style.defaults()
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    page.padding = style.EdgeLengths { left: style.Length { Px: margin() }, top: style.Length { Px: margin() }, right: style.Length { Px: margin() }, bottom: style.Length { Px: margin() } }
    page.width = style.Length { Percent: 100.0 }
    page.height = style.Length { Percent: 100.0 }
    let rows = rows_of(cells.len, columns)
    let (row_nodes, rows_error) = mem.alloc[widget.Node](a, rows)
    if rows_error != ok { ret (zero, rows_error) }
    var caption = control.text_options()
    caption.role = .BodySmall
    caption.wrap = .None
    var row = 0usize
    while row < rows {
        let first = row * columns
        var last = first + columns
        if last > cells.len { last = cells.len }
        let (boxes, boxes_error) = mem.alloc[widget.Node](a, last - first)
        if boxes_error != ok { ret (zero, boxes_error) }
        var i = first
        while i < last {
            let (label, label_error) = control.text(a, 0u64, cells[i].caption, t, caption)
            if label_error != ok { ret (zero, label_error) }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
            if parts_error != ok { ret (zero, parts_error) }
            parts[1usize] = label
            let holder = parts[1usize..2usize]
            parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, size_style(cell_w, caption_h()), holder)
            parts[2usize] = cells[i].node
            let inner = parts[2usize..3usize]
            let centred = widget.aligned(0u64, .Center, .Center, size_style(cell_w, cell_h), inner)
            let (column, column_error) = mem.alloc[widget.Node](a, 2usize)
            if column_error != ok { ret (zero, column_error) }
            column[0usize] = parts[0usize]
            column[1usize] = centred
            boxes[i - first] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), column[0usize..2usize])
            i += 1usize
        }
        row_nodes[row] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: spacing() }, style.defaults(), boxes[0usize..last - first])
        row += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: spacing() }, page, row_nodes[0usize..rows]), ok)
}

fn instant(step: i64) -> time.Instant {
    ret time.Instant { nanos: 1000000000i64 + step * 100000000i64 }
}

// One frame of `root` and its pixels.
fn shoot(rig: *Rig, root: widget.Node, step: i64) -> (image.Image, err) {
    let pumped = testing.pump(&rig.harness, root, instant(step))
    if pumped != ok { ret (zero, pumped) }
    let (shot, shot_error) = testing.snapshot(&rig.harness, rig.a)
    ret (shot, shot_error)
}

fn write_png(a: *mem.Arena, path: str, view: image.ConstImage) -> err {
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try png.encode(&writer, view, png.EncodeOptions { compression: .Balanced, interlace: false })
    ret fs.write_file(a, path, io.memory_bytes(&held))
}

fn const_view(shot: image.Image) -> image.ConstImage {
    ret image.ConstImage { pixels: shot.pixels, width: shot.width, height: shot.height, stride: shot.stride, format: shot.format, alpha: shot.alpha }
}

// Pumps one frame of `root` and writes it to `path` (directories made).
fn render(rig: *Rig, root: widget.Node, path: str) -> err {
    let (shot, shot_error) = shoot(rig, root, 0i64)
    if shot_error != ok { ret shot_error }
    ret write_png(rig.a, path, const_view(shot))
}

// What a driven cell needs the runtime to have seen before its frame.
fn drive_cell(rig: *Rig, drive: Drive, x: f32, y: f32) -> err {
    if drive == .Hover { ret testing.hover(&rig.harness, x, y) }
    if drive == .Press {
        try testing.hover(&rig.harness, x, y)
        ret testing.send(&rig.harness, input.Event { PointerDown: testing.pointer_at(x, y) })
    }
    if drive == .Focus {
        // A click focuses it by pointer; Tab and Shift+Tab bring the keyboard focus back
        // to it (a ring only shows for keyboard focus), then the pointer leaves.
        try testing.tap(&rig.harness, x, y)
        try testing.tab(&rig.harness, false)
        try testing.tab(&rig.harness, true)
        ret testing.hover(&rig.harness, -500.0, -500.0)
    }
    if drive == .Select {
        try testing.tap(&rig.harness, x, y)
        var modifiers: input.Modifiers = zero
        modifiers.control = true
        try testing.press_key(&rig.harness, 65u32, modifiers)
        ret testing.hover(&rig.harness, -500.0, -500.0)
    }
    ret ok
}

// Lets go of the button and takes the pointer away.
fn rest(rig: *Rig) -> err {
    try testing.send(&rig.harness, input.Event { PointerUp: testing.pointer_at(-500.0, -500.0) })
    ret testing.hover(&rig.harness, -500.0, -500.0)
}

// The sheet in the rig's look: a frame at rest, then for every driven cell a frame in which
// that cell's state is on, cropped over the first.
fn render_sheet(rig: *Rig, s: *const Sheet, path: str) -> (image.Image, err) {
    let a = rig.a
    let t = theme_of(rig)
    let (cells, cells_error) = mem.alloc[Cell](a, s.cells)
    if cells_error != ok { ret (zero, cells_error) }
    var step = 0i64
    let frame_one = begin(rig)
    let (count, build_error) = s.build(s.ctx, frame_one, &t, cells)
    if build_error != ok { ret (zero, build_error) }
    let (root, root_error) = sheet(frame_one, &t, cells[0usize..count], s.columns, s.cell_w, s.cell_h)
    if root_error != ok { ret (zero, root_error) }
    // One frame first so the runtime has a layout to hit-test.
    let (base, base_error) = shoot(rig, root, step)
    if base_error != ok { ret (zero, base_error) }
    var i = 0usize
    while i < count {
        let drive = cells[i].drive
        if drive != .None {
            let origin = cell_origin(s, i)
            let cx = origin.x + s.cell_w * 0.5
            let cy = origin.y + s.cell_h * 0.5
            try drive_cell(rig, drive, cx, cy)
            // Rebuild: a control reads the interaction state when it is built.
            step += 1i64
            let pass = begin(rig)
            let (again, again_error) = s.build(s.ctx, pass, &t, cells)
            if again_error != ok { ret (zero, again_error) }
            let (tree, tree_error) = sheet(pass, &t, cells[0usize..again], s.columns, s.cell_w, s.cell_h)
            if tree_error != ok { ret (zero, tree_error) }
            let (first_shot, shot_error) = shoot(rig, tree, step)
            if shot_error != ok { ret (zero, shot_error) }
            var shot = first_shot
            // (pickers) A hover that opens something lands on the element the first frame
            // built: the pointer moves again over that layout, and the frame is taken again.
            if drive == .Hover {
                try testing.hover(&rig.harness, cx, cy)
                step += 1i64
                let pass_two = begin(rig)
                let (twice, twice_error) = s.build(s.ctx, pass_two, &t, cells)
                if twice_error != ok { ret (zero, twice_error) }
                let (tree_two, tree_two_error) = sheet(pass_two, &t, cells[0usize..twice], s.columns, s.cell_w, s.cell_h)
                if tree_two_error != ok { ret (zero, tree_two_error) }
                let (shot_two, shot_two_error) = shoot(rig, tree_two, step)
                if shot_two_error != ok { ret (zero, shot_two_error) }
                shot = shot_two
            }
            let x0 = usize(origin.x * rig.scale + 0.5)
            let y0 = usize(origin.y * rig.scale + 0.5)
            let w = u32(s.cell_w * rig.scale + 0.5)
            let h = u32(s.cell_h * rig.scale + 0.5)
            let from = y0 * shot.stride + x0 * 4usize
            let crop = image.ConstImage { pixels: shot.pixels[from..shot.pixels.len], width: w, height: h, stride: shot.stride, format: shot.format, alpha: shot.alpha }
            try image.copy(base, crop, geometry.Point { x: f32(x0), y: f32(y0) })
            try rest(rig)
        }
        i += 1usize
    }
    try write_png(a, path, const_view(base))
    ret (base, ok)
}

fn scale_suffix(scale: f32) -> str {
    if scale > 1.25 { ret "@1.5x" }
    ret ""
}

fn path_of(a: *mem.Arena, look: str, name: str, tail: str, scale: f32, ext: str) -> (str, err) {
    let parts = [8]str{ out_root(), "/", look, "/", name, tail, scale_suffix(scale), ext }
    let (joined, joined_error) = strs.join(a, parts[0usize..8usize], "")
    if joined_error != ok { ret (zero, joined_error) }
    ret (joined, ok)
}

// The reference left, ours right, on the look's own background colour.
fn beside(a: *mem.Arena, reference: image.ConstImage, ours: image.Image, path: str) -> err {
    let gap = 16u32
    var h = reference.height
    if ours.height > h { h = ours.height }
    let (both, both_error) = image.allocate(a, reference.width + gap + ours.width, h, .Rgba8, .Premultiplied)
    if both_error != ok { ret both_error }
    image.clear(both, paint.rgba(1.0, 0.0, 1.0, 1.0))
    try image.copy(both, reference, geometry.Point { x: 0.0, y: 0.0 })
    try image.copy(both, const_view(ours), geometry.Point { x: f32(reference.width + gap), y: 0.0 })
    ret write_png(a, path, const_view(both))
}

fn load_reference(a: *mem.Arena, path: str) -> (image.Image, bool) {
    let (present, present_error) = fs.exists(a, path)
    if present_error != ok || !present { ret (zero, false) }
    let (bytes, read_error) = fs.read_file(a, path, 67108864usize)
    if read_error != ok { ret (zero, false) }
    var state: io.SliceReader = zero
    state.data = bytes
    state.off = 0usize
    let (decoded, decode_error) = png.decode(a, io.slice_reader(&state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: false })
    if decode_error != ok { ret (zero, false) }
    ret (decoded, true)
}

// Renders `s` under the Neper, Windows and Windows dark looks at 100 % and 150 %.
fn run_all(a: *mem.Arena, s: *const Sheet) -> err {
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        var look_index = 0usize
        while look_index < 3usize {
            var look: Look = .Neper
            if look_index == 1usize { look = .Windows }
            if look_index == 2usize { look = .WindowsDark }
            let (rig, open_error) = open(a, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(a, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(a, folder)
            let (path, path_error) = path_of(a, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            if look == .Windows {
                let (reference_path, reference_path_error) = path_of(a, "ref/windows", s.name, "", scale, ".png")
                if reference_path_error != ok { ret reference_path_error }
                let (reference, has_reference) = load_reference(a, reference_path)
                if has_reference {
                    let (pair_path, pair_error) = path_of(a, "windows", s.name, "-vs-ref", scale, ".png")
                    if pair_error != ok { ret pair_error }
                    try beside(a, const_view(reference), ours, pair_path)
                }
            }
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}

// The Cupertino looks, Light and Dark, at 100 % and 150 %: docs/ui/looks/cupertino and cupertino-dark.
fn run_cupertino(a: *mem.Arena, s: *const Sheet) -> err {
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        var look_index = 0usize
        while look_index < 2usize {
            var look: Look = .Cupertino
            if look_index == 1usize { look = .CupertinoDark }
            let (rig, open_error) = open(a, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(a, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(a, folder)
            let (path, path_error) = path_of(a, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}
