// An e.ui app on Android (L182, D5910): ui_counter's count and buttons, as a NativeActivity. `ANativeActivity_onCreate`
// hands `run` to x.android.activity, which runs it with the activity's window and touches as an e.os window; frames go
// through GLES (x.khronos.present.install_es). Each change of the count is logged, so `adb logcat -s neper` follows it.
// The font is the system's Roboto. Pack and run:
//   scripts/build-apk.ps1 -Source examples/android/counter/src/main.e -Package dev.neper.counter -Out build/android/counter.apk

use e.fs
use e.mem
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
use x.android.activity
use x.khronos.present

@import("liblog.so", "__android_log_write")
extern fn log_write(priority: i32, tag: *const u8, text: *const u8) -> i32

const KEY_COUNT: u64 = 2u64
const KEY_INCREMENT: u64 = 3u64
const KEY_QUIT: u64 = 6u64

type Model = struct {
    tokens: style.ThemeTokens,
    fonts: []shape.Font,
    storage: []u8,
    frame: mem.Arena,
    registered: bool,
    count: usize,
    quit: bool,
}

fn say(a: *mem.Arena, text: str) {
    let (b, b_error) = str.builder(a, 128usize)
    if b_error != ok { ret }
    var sb = b
    if str.push(&sb, text) != ok || str.push(&sb, "\x00") != ok { ret }
    let line = str.done(&sb)
    let tag = "neper\x00"
    let logged = log_write(4i32, &tag[0usize], &line[0usize])
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

fn submit(a: *mem.Arena, m: *Model, f: fn(*void) -> err) -> *widget.Submit {
    var none_at_all: *widget.Submit = zero
    let (one, one_error) = mem.alloc[widget.Submit](a, 1usize)
    if one_error != ok { ret none_at_all }
    one[0usize] = widget.Submit { ctx: mem.cast[*void](m), invoke: f }
    ret &one[0usize]
}

fn counted(a: *mem.Arena, n: usize) -> str {
    let (b, b_error) = str.builder(a, 64usize)
    if b_error != ok { ret "Count" }
    var sb = b
    if str.push(&sb, "Count: ") != ok || str.push_usize(&sb, n) != ok { ret "Count" }
    ret str.done(&sb)
}

fn title(a: *mem.Arena, t: *const control.Theme, key: u64, value: str, role: style.TextRole) -> (widget.Node, err) {
    var options = control.text_options()
    options.role = role
    let (node, node_error) = control.text(a, key, value, t, options)
    ret (node, node_error)
}

fn build(m: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    m.frame = mem.arena_from(m.storage)
    let a = &m.frame
    if !m.registered {
        if scene.register_font(widget.renderer_of(ctx.runtime), m.fonts[0usize]) != ok { ret (zero, control.TooLarge) }
        m.registered = true
    }
    let theme = control.Theme { tokens: &m.tokens, fonts: m.fonts, language: "en", runtime: ctx.runtime }
    let t = &theme
    let (heading, heading_error) = title(a, t, 1u64, "Counter", .Title)
    if heading_error != ok { ret (zero, heading_error) }
    let (count, count_error) = title(a, t, KEY_COUNT, counted(a, m.count), .Body)
    if count_error != ok { ret (zero, count_error) }
    let (increment, increment_error) = control.button(a, KEY_INCREMENT, t, "Increment", submit(a, m, on_increment), control.button_options())
    if increment_error != ok { ret (zero, increment_error) }
    let (quit, quit_error) = control.button(a, KEY_QUIT, t, "Quit", submit(a, m, on_quit), control.button_options())
    if quit_error != ok { ret (zero, quit_error) }
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, 4usize)
    if nodes_error != ok { ret (zero, nodes_error) }
    nodes[0usize] = heading
    nodes[1usize] = count
    nodes[2usize] = increment
    nodes[3usize] = quit
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.md }, style.defaults(), nodes[0usize..4usize])
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

fn run(a: *mem.Arena) -> err {
    present.install_es()
    let (font_bytes, font_error) = fs.read_file(a, "/system/fonts/Roboto-Regular.ttf", 16777216usize)
    if font_error != ok {
        say(a, "no system font")
        ret font_error
    }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { ret fonts_error }
    fonts[0usize] = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { ret storage_error }
    let (models, models_error) = mem.alloc[Model](a, 1usize)
    if models_error != ok { ret models_error }
    var m: Model = zero
    m.tokens = style.reference(.Light)
    m.fonts = fonts
    m.storage = storage
    models[0usize] = m
    let model = &models[0usize]
    let options = app.Options {
        window: window.Options { title: "counter", width: 480u32, height: 320u32, min_width: 0u32, min_height: 0u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 256usize, max_states: 64usize, state_bytes: 512usize, state_classes: 8u16, max_depth: 16u16, max_commands: 4096usize },
        frame_arena_bytes: 4194304usize,
        event_capacity: 256usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: model, build: build })
    if init_error != ok {
        say(a, "no window")
        ret init_error
    }
    var running = application
    let (shown_window, shown_window_error) = app.window_of(&running)
    if shown_window_error == ok && window.presenting(shown_window) { say(a, "ready, presenting through GLES") } else { say(a, "ready, presenting in software") }
    var shown_count = 0usize
    while !model.quit {
        let (more, step_error) = app.step(&running, time.millis(50i64))
        if step_error != ok { ret step_error }
        if !more { break }
        if model.count != shown_count {
            shown_count = model.count
            say(a, counted(a, shown_count))
        }
    }
    let closed = app.close(&running)
    say(a, "bye")
    ret ok
}

@export("ANativeActivity_onCreate")
@cc(c)
fn on_create(native_activity: *void, saved_state: *void, saved_state_size: usize) {
    activity.start(mem.address_of(native_activity), run)
}
