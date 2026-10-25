// A window in a page (D5680, C193): a title, a count with a button that raises it, a text field with a greeting
// under it, and a button that quits. Every change is also printed ("count N", "name TEXT") so a test can read
// the program's state without the pixels, and once the first frame has been laid out the button and field
// rectangles are printed ("layout KEY X Y W H", logical pixels) so a test can click them.
// The font is /jost-regular.ttf in the file system (the page seeds it with `files`).
//
//   neper emit-executable tests/wasm/browser/ui_counter/src/main.e . wasm32 wasi ui_counter.wasm

use e.fs
use e.gpu
use e.io
use e.mem
use e.os
use e.str
use e.time
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.app
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

const KEY_COUNT: u64 = 2u64
const KEY_INCREMENT: u64 = 3u64
const KEY_NAME: u64 = 4u64
const KEY_QUIT: u64 = 6u64

type Model = struct {
    tokens: style.ThemeTokens,
    fonts: []shape.Font,
    storage: []u8,
    frame: mem.Arena,
    registered: bool,
    count: usize,
    name: [64]u8,
    name_len: usize,
    quit: bool,
    laid_out: bool,
    builds: usize,
}

fn on_increment(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.count += 1usize
    ret ok
}

fn on_quit(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    m.quit = true
    ret ok
}

fn on_name(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.name_len = value.len
    ret ok
}

fn submit(a: *mem.Arena, m: *Model, f: fn(*void) -> err) -> *widget.Submit {
    var none_at_all: *widget.Submit = zero
    let (one, one_error) = mem.alloc[widget.Submit](a, 1usize)
    if one_error != ok { ret none_at_all }
    one[0usize] = widget.Submit { ctx: mem.cast[*void](m), invoke: f }
    ret &one[0usize]
}

fn joined(a: *mem.Arena, prefix: str, tail: str) -> str {
    let (b, b_error) = str.builder(a, 128usize)
    if b_error != ok { ret prefix }
    var sb = b
    if str.push(&sb, prefix) != ok || str.push(&sb, tail) != ok { ret prefix }
    ret str.done(&sb)
}

fn counted(a: *mem.Arena, n: usize) -> str {
    let (b, b_error) = str.builder(a, 64usize)
    if b_error != ok { ret "Count" }
    var sb = b
    if str.push(&sb, "Count: ") != ok || str.push_usize(&sb, n) != ok { ret "Count" }
    ret str.done(&sb)
}

fn report(a: *mem.Arena, runtime: *widget.Runtime, key: u64) {
    let (element, found) = widget.find_by_key(mem.cast[*widget.State](runtime.state), key)
    if found != 1usize { ret }
    let (bounds, has_bounds) = widget.bounds_of(runtime, element)
    if !has_bounds { ret }
    let (b, b_error) = str.builder(a, 96usize)
    if b_error != ok { ret }
    var sb = b
    if str.push(&sb, "layout ") != ok || str.push_usize(&sb, usize(key)) != ok { ret }
    if str.push(&sb, " ") != ok || str.push_usize(&sb, usize(bounds.x)) != ok { ret }
    if str.push(&sb, " ") != ok || str.push_usize(&sb, usize(bounds.y)) != ok { ret }
    if str.push(&sb, " ") != ok || str.push_usize(&sb, usize(bounds.width)) != ok { ret }
    if str.push(&sb, " ") != ok || str.push_usize(&sb, usize(bounds.height)) != ok { ret }
    if str.push(&sb, "\n") != ok { ret }
    let written = io.print(str.done(&sb))
}

fn title(a: *mem.Arena, t: *const control.Theme, key: u64, value: str, role: style.TextRole) -> (widget.Node, err) {
    var options = control.text_options()
    options.role = role
    let (node, node_error) = control.text(a, key, value, t, options)
    ret (node, node_error)
}

fn build(m: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    m.builds += 1usize
    if m.builds < 3usize { widget.request_animation_frame(ctx.runtime) }
    m.frame = mem.arena_from(m.storage)
    let a = &m.frame
    if !m.registered {
        if scene.register_font(widget.renderer_of(ctx.runtime), m.fonts[0usize]) != ok { ret (zero, control.TooLarge) }
        m.registered = true
    }
    if m.builds == 3usize && !m.laid_out {
        m.laid_out = true
        report(a, ctx.runtime, KEY_INCREMENT)
        report(a, ctx.runtime, KEY_NAME)
        report(a, ctx.runtime, KEY_QUIT)
    }
    let theme = control.Theme { tokens: &m.tokens, fonts: m.fonts, language: "en", runtime: ctx.runtime }
    let t = &theme
    let (heading, heading_error) = title(a, t, 1u64, "Counter", .Title)
    if heading_error != ok { ret (zero, heading_error) }
    let (count, count_error) = title(a, t, KEY_COUNT, counted(a, m.count), .Body)
    if count_error != ok { ret (zero, count_error) }
    let (increment, increment_error) = control.button(a, KEY_INCREMENT, t, "Increment", submit(a, m, on_increment), control.button_options())
    if increment_error != ok { ret (zero, increment_error) }
    var field_options = control.field_options()
    field_options.placeholder = "Your name"
    let (name, name_error) = control.text_field(a, KEY_NAME, t, "Name", m.name[..], m.name_len, widget.Change[str] { ctx: mem.cast[*void](m), invoke: on_name }, zero, field_options)
    if name_error != ok { ret (zero, name_error) }
    var greeting_text = "Hello, stranger"
    if m.name_len > 0usize { greeting_text = joined(a, "Hello, ", m.name[0usize..m.name_len]) }
    let (greeting, greeting_error) = title(a, t, 5u64, greeting_text, .Body)
    if greeting_error != ok { ret (zero, greeting_error) }
    let (quit, quit_error) = control.button(a, KEY_QUIT, t, "Quit", submit(a, m, on_quit), control.button_options())
    if quit_error != ok { ret (zero, quit_error) }
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 6usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    nodes[0usize] = heading
    nodes[1usize] = count
    nodes[2usize] = increment
    nodes[3usize] = name
    nodes[4usize] = greeting
    nodes[5usize] = quit
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.md }, style.defaults(), nodes[0usize..6usize])
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = column
    let gap = t.tokens.spacing.lg
    var root = style.defaults()
    root.width = style.Length { Percent: 100.0 }
    root.height = style.Length { Percent: 100.0 }
    root.background = paint.Brush { Solid: style.color(&m.tokens, .Background) }
    ret (widget.padded(0u64, gap, gap, gap, gap, root, inner[0usize..1usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "/jost-regular.ttf", 16777216usize)
    if font_error != ok {
        try io.print("no UI font: seed /jost-regular.ttf\n")
        os.exit(2i32)
    }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(1i32) }
    fonts[0usize] = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(1i32) }
    let (models, models_error) = mem.alloc[Model](a, 1usize)
    if models_error != ok { os.exit(1i32) }
    var m: Model = zero
    m.tokens = style.reference(.Light)
    m.fonts = fonts
    m.storage = storage
    models[0usize] = m
    let model = &models[0usize]
    let options = app.Options {
        window: window.Options { title: "ui_counter", width: 480u32, height: 320u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 256usize, max_states: 64usize, state_bytes: 512usize, state_classes: 8u16, max_depth: 16u16, max_commands: 4096usize },
        frame_arena_bytes: 4194304usize,
        event_capacity: 256usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: model, build: build })
    if init_error != ok {
        try io.print("the host cannot open a window\n")
        os.exit(3i32)
    }
    var running = application
    var shown_count = 0usize
    var shown_name = 0usize
    try io.print("ready\n")
    while !model.quit {
        let (more, step_error) = app.step(&running, time.millis(50i64))
        if step_error != ok { os.exit(4i32) }
        if !more { break }
        if model.count != shown_count {
            shown_count = model.count
            let (b, b_error) = str.builder(a, 32usize)
            if b_error == ok {
                var sb = b
                let pushed = str.push(&sb, "count ")
                let number = str.push_usize(&sb, shown_count)
                let line = str.push(&sb, "\n")
                try io.print(str.done(&sb))
            }
        }
        if model.name_len != shown_name {
            shown_name = model.name_len
            try io.print(joined(a, "name ", joined(a, str_of(model.name[0usize..shown_name]), "\n")))
        }
    }
    let closed = app.close(&running)
    try io.print("bye\n")
    ret ok
}

fn str_of(bytes: []const u8) -> str { ret bytes }
