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
use e.os
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
type Look = enum u8 { Neper, Windows, Cupertino, Material, WindowsDark, MaterialDark, CupertinoDark, NeperDark, Linux, LinuxDark }
// How a cell's state is produced: None (at rest, or whatever the build made of it, for example
// disabled), Hover (the pointer over it), Press (the primary button held on it), Focus (keyboard
// focus, ring visible), Select (focus, then Ctrl+A: an edit's whole text selected).
type Drive = enum u8 { None, Hover, Press, Focus, Select, SelectPress, Caret2, Caret33, FocusHover }
type Cell = struct { caption: str, node: widget.Node, drive: Drive }
// Fills `cells` (up to its length) with the control in its states and answers how many; called
// again for every driven cell, so it must build the same keys every time. Control keys must be
// unique in the sheet and non-zero.
type Build = fn(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []Cell) -> (usize, err)
// A sheet: `name` is the file stem (the control), `columns` cells per row, each cell a box of
// `cell_w` x `cell_h` logical px with the control centred in it and its caption above.
type Sheet = struct { name: str, cells: usize, columns: usize, cell_w: f32, cell_h: f32, ctx: *void, build: Build }
type Rig = struct { a: *mem.Arena, device: *gpu.Device, renderer: scene.Renderer, runtime: widget.Runtime, harness: testing.Harness, tokens: style.ThemeTokens, fonts: []shape.Font, frame_storage: []u8, frame: mem.Arena, flip: bool, width: f32, height: f32, scale: f32, material_fonts: []shape.Font, linux_fonts: []shape.Font }
error Failed

// looks5-e: where a driven cell's pointer goes, as an offset from the cell's centre (default none): an app sets it
// from `build` for the cells it needs (a button of a large control that is not at the centre).
var aim_x: [64]f32 = zero
var aim_y: [64]f32 = zero
fn aim(i: usize, dx: f32, dy: f32) {
    if i < 64usize {
        aim_x[i] = dx
        aim_y[i] = dy
    }
}

fn margin() -> f32 { ret 12.0 }
fn spacing() -> f32 { ret 10.0 }
fn caption_h() -> f32 { ret 16.0 }
fn out_root() -> str { ret "docs/ui/looks" }
fn segoe_path() -> str { ret "C:/Windows/Fonts/segoeui.ttf" }
fn tahoma_path() -> str { ret "C:/Windows/Fonts/tahoma.ttf" }
fn roboto_path() -> str { ret "C:/Windows/Fonts/Roboto-Regular.ttf" }
fn roboto_medium_path() -> str { ret "C:/Windows/Fonts/Roboto-Medium.ttf" }
// Segoe UI Bold (font id 9), last in the chain: only a control that asks for weight 700 reaches it.
fn segoe_bold_path() -> str { ret "C:/Windows/Fonts/segoeuib.ttf" }
// Tahoma Bold (font id 10), last: v3 draws bold labels, captions, the Options pages' header title and the bars' group headers in it.
fn tahoma_bold_path() -> str { ret "C:/Windows/Fonts/tahomabd.ttf" }
// The Linux look's Cantarell (SIL OFL, converted from the distro's OTF to TrueType by scripts/linux/otf2ttf.py: this text
// engine reads glyf outlines only), font ids 13 and 14, read by `run_linux` alone (so the other looks need nothing).
fn cantarell_path() -> str { ret "docs/ui/looks/ref/linux/fonts/Cantarell-Regular.ttf" }
fn cantarell_bold_path() -> str { ret "docs/ui/looks/ref/linux/fonts/Cantarell-Bold.ttf" }

// The tokens of a look, Light palette. Cupertino and Material are planned: the Neper tokens
// with the matching profile, so a control that branches on it can start to.
fn theme_for(look: Look) -> style.ThemeTokens {
    if look == .Windows { ret style.windows(.Light) }
    if look == .WindowsDark { ret style.windows(.Dark) }
    if look == .NeperDark { ret style.reference(.Dark) }
    if look == .Material { ret style.material(.Light) }
    if look == .Linux { ret style.adwaita(.Light) }
    if look == .LinuxDark { ret style.adwaita(.Dark) }
    if look == .MaterialDark { ret style.material(.Dark) }
    if look == .Cupertino { ret style.cupertino(.Light) }
    if look == .CupertinoDark { ret style.cupertino(.Dark) }
    var t = style.reference(.Light)
    ret t
}

fn look_dir(look: Look) -> str {
    if look == .Windows { ret "windows" }
    if look == .WindowsDark { ret "windows-dark" }
    if look == .NeperDark { ret "neper-dark" }
    if look == .Cupertino { ret "cupertino" }
    if look == .CupertinoDark { ret "cupertino-dark" }
    if look == .Material { ret "material" }
    if look == .Linux { ret "linux" }
    if look == .LinuxDark { ret "linux-dark" }
    if look == .MaterialDark { ret "material-dark" }
    ret "neper"
}

// The font files and the frame storage, read and allocated by the first rig and shared by the rest.
var shared_fonts: [6][]u8 = zero
var shared_fonts_read: bool = false
var shared_linux: [2][]u8 = zero
var shared_linux_read: bool = false
var shared_storage: []u8 = zero

fn read_fonts(a: *mem.Arena) -> err {
    if shared_fonts_read { ret ok }
    let sa = stable(a)
    let paths = [6]str{ segoe_path(), tahoma_path(), segoe_bold_path(), tahoma_bold_path(), roboto_path(), roboto_medium_path() }
    var i = 0usize
    while i < 6usize {
        let (bytes, read_error) = fs.read_file(sa, paths[i], 16777216usize)
        if read_error != ok { ret read_error }
        shared_fonts[i] = bytes
        i += 1usize
    }
    shared_fonts_read = true
    ret ok
}

fn read_linux_fonts(a: *mem.Arena) -> err {
    if shared_linux_read { ret ok }
    let sa = stable(a)
    let (regular, regular_error) = fs.read_file(sa, cantarell_path(), 16777216usize)
    if regular_error != ok { ret regular_error }
    let (bold, bold_error) = fs.read_file(sa, cantarell_bold_path(), 16777216usize)
    if bold_error != ok { ret bold_error }
    shared_linux[0usize] = regular
    shared_linux[1usize] = bold
    shared_linux_read = true
    ret ok
}

// The rigs of a run live in one scratch arena, emptied (and zeroed, as fresh arena memory is) before each
// rig, so a process can run any number of sheets; what must outlive a rig (the font files, the frame
// storage, an app's own state in the arena the app main got) lives in `stable`, the arena of the first run.
var stable_arena: *mem.Arena = zero
var rig_chunk: []u8 = zero
var rig_arenas: []mem.Arena = zero

fn stable(a: *mem.Arena) -> *mem.Arena {
    if mem.address_of(stable_arena) == 0usize { ret a }
    ret stable_arena
}

// The scratch arena for the next rig, empty.
fn rig_scope(a: *mem.Arena) -> *mem.Arena {
    if mem.address_of(stable_arena) == 0usize { stable_arena = a }
    if rig_chunk.len == 0usize {
        let (chunk, chunk_error) = mem.alloc[u8](stable_arena, 805306368usize)
        if chunk_error != ok { ret stable_arena }
        rig_chunk = chunk
        let (holder, holder_error) = mem.alloc[mem.Arena](stable_arena, 1usize)
        if holder_error != ok { ret stable_arena }
        rig_arenas = holder
    } else {
        var i = 0usize
        while i < rig_arenas[0usize].off {
            rig_chunk[i] = 0u8
            i += 1usize
        }
    }
    rig_arenas[0usize] = mem.arena_from(rig_chunk)
    ret &rig_arenas[0usize]
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
    try read_fonts(a)
    let segoe_bytes = shared_fonts[0usize]
    let tahoma_bytes = shared_fonts[1usize]
    let bold_bytes = shared_fonts[2usize]
    let tahoma_bold_bytes = shared_fonts[3usize]
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret (rig, device_error) }
    rig.device = device
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (rig, queue_error) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 64u32)
    if renderer_error != ok { ret (rig, renderer_error) }
    rig.renderer = r
    // The Android look: Roboto Regular (id 11) and Medium (id 12), led by themselves, then the Windows faces for glyphs Roboto lacks.
    let roboto_bytes = shared_fonts[4usize]
    let medium_bytes = shared_fonts[5usize]
    let (droid, droid_error) = mem.alloc[shape.Font](a, 6usize)
    if droid_error != ok { ret (rig, droid_error) }
    droid[0usize] = shape.Font { id: 11u32, data: roboto_bytes, face_index: 0u32 }
    droid[1usize] = shape.Font { id: 12u32, data: medium_bytes, face_index: 0u32 }
    droid[2usize] = shape.Font { id: 7u32, data: segoe_bytes, face_index: 0u32 }
    droid[3usize] = shape.Font { id: 9u32, data: bold_bytes, face_index: 0u32 }
    droid[4usize] = shape.Font { id: 8u32, data: tahoma_bytes, face_index: 0u32 }
    droid[5usize] = shape.Font { id: 10u32, data: tahoma_bold_bytes, face_index: 0u32 }
    try scene.register_font(&rig.renderer, droid[0usize])
    try scene.register_font(&rig.renderer, droid[1usize])
    rig.material_fonts = droid[0usize..6usize]
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
    // The Linux look: Cantarell Regular (id 13) and Bold (14) lead, the Windows faces follow for glyphs Cantarell lacks.
    if shared_linux_read {
        let (gtk, gtk_error) = mem.alloc[shape.Font](a, 6usize)
        if gtk_error != ok { ret (rig, gtk_error) }
        gtk[0usize] = shape.Font { id: 13u32, data: shared_linux[0usize], face_index: 0u32 }
        gtk[1usize] = shape.Font { id: 14u32, data: shared_linux[1usize], face_index: 0u32 }
        gtk[2usize] = fonts[0usize]
        gtk[3usize] = fonts[2usize]
        gtk[4usize] = fonts[1usize]
        gtk[5usize] = fonts[3usize]
        try scene.register_font(&rig.renderer, gtk[0usize])
        try scene.register_font(&rig.renderer, gtk[1usize])
        rig.linux_fonts = gtk[0usize..6usize]
    }
    let (rt, runtime_error) = widget.runtime(a, &rig.renderer, widget.Limits { max_elements: 16384usize, max_states: 1024usize, state_bytes: 65536usize, state_classes: 8u16, max_depth: 48u16, max_commands: 49152usize })
    if runtime_error != ok { ret (rig, runtime_error) }
    rig.runtime = rt
    // The app sets this from the window; here, so that pixel art lands on whole device pixels. Left alone at 100 %.
    if scale != 1.0 { widget.set_snap(&rig.runtime, 1.0 / scale) }
    let physical_w = u32(width * scale + 0.5)
    let physical_h = u32(height * scale + 0.5)
    let (h, harness_error) = testing.harness(a, &rig.runtime, physical_w, physical_h, scale)
    if harness_error != ok { ret (rig, harness_error) }
    rig.harness = h
    if shared_storage.len == 0usize {
        let (storage, storage_error) = mem.alloc[u8](stable(a), 33554432usize)
        if storage_error != ok { ret (rig, storage_error) }
        shared_storage = storage
    }
    rig.frame_storage = shared_storage
    rig.frame = mem.arena_from(shared_storage)
    rig.tokens = theme_for(.Neper)
    ret (rig, ok)
}

// Lets go of the rig's device (its registry slot: a process has only 16 of them) and renderer. The
// rig's arena memory is not given back (an app may allocate its own state in `a` after the first rig), so
// the big parts of a rig, the font files and the frame storage, are shared by all the rigs of a process.
fn close_rig(rig: *Rig) {
    let h = testing.close(&rig.harness)
    let r = scene.close(&rig.renderer)
    let d = gpu.close(rig.device)
}

fn set_look(rig: *Rig, look: Look) {
    style.set_windark(false)
    rig.tokens = theme_for(look)
    // The Windows dark look maps the light literals of its tile painters (style.hex) to dark; nothing else does.
    style.set_windark(look == .WindowsDark)
    widget.set_arc_corners(rig.tokens.profile == .MaterialLike || rig.tokens.profile == .Linux)
    scene.set_pixel_exact(rig.tokens.profile == .Windows)
    // The Windows profile draws text as ClearType (hinted, per-subpixel coverage); every other look keeps the greyscale fill.
    // NEPER_TEXT_AA=grayscale draws the Windows looks that way too, NEPER_TEXT_AA=cleartype draws every look in ClearType.
    var text_aa = scene.TextAa.Grayscale
    if rig.tokens.profile == .Windows { text_aa = scene.TextAa.ClearType }
    let (aa_text, aa_error) = os.env(rig.a, "NEPER_TEXT_AA")
    if aa_error == ok && strs.eq(aa_text, "grayscale") { text_aa = scene.TextAa.Grayscale }
    if aa_error == ok && strs.eq(aa_text, "cleartype") { text_aa = scene.TextAa.ClearType }
    scene.set_text_aa(text_aa)
    let (exact_text, exact_error) = os.env(rig.a, "NEPER_LOOKS_EXACT")
    scene.set_pixel_exact_at_one(exact_error == ok && exact_text.len > 0usize)
    if look == .Material || look == .MaterialDark { rig.fonts = rig.material_fonts }
    if (look == .Linux || look == .LinuxDark) && rig.linux_fonts.len > 0usize { rig.fonts = rig.linux_fonts }
}

// The control theme of the rig: its tokens, fonts and runtime.
fn theme_of(rig: *Rig) -> control.Theme {
    ret control.Theme { tokens: &rig.tokens, fonts: rig.fonts, language: "", runtime: &rig.runtime }
}

// The frame arena, emptied: everything built for one pass lives in it.
// The pass before it is kept whole: the runtime holds the text buffers a pass built (an edit's `buffer` slice) until the
// next pump, and a control reads them while it is built (a multi-line edit asks for its caret line), so the passes
// alternate between the two halves of the storage and never overwrite what the runtime still points into.
fn begin(rig: *Rig) -> *mem.Arena {
    rig.flip = !rig.flip
    let half = rig.frame_storage.len / 2usize
    if rig.flip {
        rig.frame = mem.arena_from(rig.frame_storage[half..rig.frame_storage.len])
    } else {
        rig.frame = mem.arena_from(rig.frame_storage[0usize..half])
    }
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

// Where the last frame's pixels start in the rig arena: a sheet takes one frame per driven cell, and the sheet's
// size at 2.0 times a hundred cells is more than the arena, so a frame's pixels are dropped (`drop_shot`) once the
// cell has been cropped out of them.
var shot_from: usize = 0

fn drop_shot(rig: *Rig) {
    mem.reset(rig.a, shot_from)
}

// One frame of `root` and its pixels.
fn shoot(rig: *Rig, root: widget.Node, step: i64) -> (image.Image, err) {
    let pumped = testing.pump(&rig.harness, root, instant(step))
    if pumped != ok { ret (zero, pumped) }
    shot_from = rig.a.off
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
    if drive == .FocusHover {
        // The keyboard focus in an edit (the click lands 60 px left of the point), then the pointer over the point.
        try testing.tap(&rig.harness, x - 60.0, y)
        ret testing.hover(&rig.harness, x, y)
    }
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
    if drive == .SelectPress {
        // An edit with its text selected and an end button pressed (a button edit's ellipsis): the click that focuses the
        // edit lands 60 px left of the point, Ctrl+A selects, then the button at the point is held down.
        try testing.tap(&rig.harness, x - 60.0, y)
        var chord: input.Modifiers = zero
        chord.control = true
        try testing.press_key(&rig.harness, 65u32, chord)
        try testing.hover(&rig.harness, x, y)
        ret testing.send(&rig.harness, input.Event { PointerDown: testing.pointer_at(x, y) })
    }
    if drive == .Caret2 || drive == .Caret33 {
        // Focus, then the caret put after the 2nd or the 33rd character (a pointer click does not place it in the harness):
        // the captures show a clicked edit with its caret mid-text.
        try testing.tap(&rig.harness, x, y)
        var none: input.Modifiers = zero
        try testing.press_key(&rig.harness, 36u32, none)
        var count = 2usize
        if drive == .Caret33 { count = 33usize }
        var n = 0usize
        while n < count {
            try testing.press_key(&rig.harness, 39u32, none)
            n += 1usize
        }
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
            var cx = origin.x + s.cell_w * 0.5
            var cy = origin.y + s.cell_h * 0.5
            if i < 64usize {
                cx += aim_x[i]
                cy += aim_y[i]
            }
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
            if drive == .Hover || drive == .FocusHover {
                drop_shot(rig)
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
            drop_shot(rig)
            try rest(rig)
        }
        i += 1usize
    }
    try write_png(a, path, const_view(base))
    ret (base, ok)
}

fn scale_suffix(scale: f32) -> str {
    if scale > 1.9 { ret "@2x" }
    if scale > 1.4 { ret "@1.5x" }
    if scale > 1.1 { ret "@1.25x" }
    ret ""
}

// The environment variable NEPER_LOOKS_SCALE (a number such as 1.25, 1.5 or 2) makes run_all render
// that one scale instead of 1.0 and 1.5, and NEPER_LOOKS_OUT names the folder to write into instead of
// docs/ui/looks, so a scale check never touches the committed PNGs. Unset, nothing changes.
fn env_scale(a: *mem.Arena) -> f32 {
    let (text, text_error) = os.env(a, "NEPER_LOOKS_SCALE")
    if text_error != ok { ret 0.0 }
    if strs.eq(text, "1.25") { ret 1.25 }
    if strs.eq(text, "1.5") { ret 1.5 }
    if strs.eq(text, "2") || strs.eq(text, "2.0") { ret 2.0 }
    if strs.eq(text, "1") || strs.eq(text, "1.0") { ret 1.0 }
    ret 0.0
}

fn env_out(a: *mem.Arena) -> str {
    let (text, text_error) = os.env(a, "NEPER_LOOKS_OUT")
    if text_error != ok || text.len == 0usize { ret out_root() }
    ret text
}

fn path_of(a: *mem.Arena, look: str, name: str, tail: str, scale: f32, ext: str) -> (str, err) {
    let parts = [8]str{ env_out(a), "/", look, "/", name, tail, scale_suffix(scale), ext }
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
    let only_scale = env_scale(a)
    let (no_text, no_text_error) = os.env(a, "NEPER_LOOKS_NOTEXT")
    scene.set_text_hidden(no_text_error == ok && no_text.len > 0usize)
    // NEPER_LOOKS_ONLY=windows renders the Windows look alone (the scale check needs nothing else).
    let (only_look, only_look_error) = os.env(a, "NEPER_LOOKS_ONLY")
    let windows_only = only_look_error == ok && strs.eq(only_look, "windows")
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        if only_scale > 0.0 {
            if scale_index == 1usize { break }
            scale = only_scale
        }
        var look_index = 0usize
        while look_index < 4usize {
            if windows_only && look_index != 1usize {
                look_index += 1usize
                continue
            }
            var look: Look = .Neper
            if look_index == 1usize { look = .Windows }
            if look_index == 2usize { look = .WindowsDark }
            if look_index == 3usize { look = .NeperDark }
            let ra = rig_scope(a)
            let (rig, open_error) = open(ra, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(ra, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = path_of(ra, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            if look == .Windows {
                let (reference_path, reference_path_error) = path_of(ra, "ref/windows", s.name, "", scale, ".png")
                if reference_path_error != ok { ret reference_path_error }
                let (reference, has_reference) = load_reference(ra, reference_path)
                if has_reference {
                    let (pair_path, pair_error) = path_of(ra, "windows", s.name, "-vs-ref", scale, ".png")
                    if pair_error != ok { ret pair_error }
                    try beside(ra, const_view(reference), ours, pair_path)
                }
            }
            close_rig(rig)
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}

// The Android look (docs/ui/looks/material, material-dark): `s` under style.material at 100 % and 150 %. Only these two
// looks are written, so a sheet can be run without touching the Neper and Windows pictures.
fn run_material(a: *mem.Arena, s: *const Sheet) -> err {
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        var look_index = 0usize
        while look_index < 2usize {
            var look: Look = .Material
            if look_index == 1usize { look = .MaterialDark }
            let ra = rig_scope(a)
            let (rig, open_error) = open(ra, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(ra, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = path_of(ra, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            close_rig(rig)
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
            let ra = rig_scope(a)
            let (rig, open_error) = open(ra, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(ra, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = path_of(ra, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            close_rig(rig)
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}

// The Linux look, Light and Dark, at 100 % and 150 %: docs/ui/looks/linux and linux-dark. Beside each, when the real GTK
// reference exists as a composite laid out like the sheet (docs/ui/looks/ref/linux/composite/{light,dark}/<name>[@1.5x].png,
// scripts/linux/compose_ref.py), docs/ui/looks/<linux dir>/<name>-vs-ref[@1.5x].png (reference left, ours right).
fn run_linux(a: *mem.Arena, s: *const Sheet) -> err {
    try read_linux_fonts(a)
    // As run_all: NEPER_LOOKS_SCALE renders that one scale and NEPER_LOOKS_NOTEXT leaves the text out (the scale check, scripts/looks_scale_check.py).
    let only_scale = env_scale(a)
    let (no_text, no_text_error) = os.env(a, "NEPER_LOOKS_NOTEXT")
    scene.set_text_hidden(no_text_error == ok && no_text.len > 0usize)
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        if only_scale > 0.0 {
            if scale_index == 1usize { break }
            scale = only_scale
        }
        var look_index = 0usize
        while look_index < 2usize {
            var look: Look = .Linux
            var scheme = "light"
            if look_index == 1usize {
                look = .LinuxDark
                scheme = "dark"
            }
            let ra = rig_scope(a)
            let (rig, open_error) = open(ra, sheet_width(s), sheet_height(s), scale)
            if open_error != ok { ret open_error }
            set_look(rig, look)
            let (folder, folder_error) = path_of(ra, look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = path_of(ra, look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = render_sheet(rig, s, path)
            if render_error != ok { ret render_error }
            let dir_parts = [2]str{ "ref/linux/composite/", scheme }
            let (reference_dir, reference_dir_error) = strs.join(ra, dir_parts[0usize..2usize], "")
            if reference_dir_error != ok { ret reference_dir_error }
            let (reference_path, reference_path_error) = path_of(ra, reference_dir, s.name, "", scale, ".png")
            if reference_path_error != ok { ret reference_path_error }
            let (reference, has_reference) = load_reference(ra, reference_path)
            if has_reference {
                let (pair_path, pair_error) = path_of(ra, look_dir(look), s.name, "-vs-ref", scale, ".png")
                if pair_error != ok { ret pair_error }
                try beside(ra, const_view(reference), ours, pair_path)
            }
            close_rig(rig)
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}
