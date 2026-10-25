// The Neper browser: a window with a tab strip, back / forward / reload buttons, an omnibox, a bookmark toggle and the page, over
// `e.web.shell` (tabs, session history, omnibox rules, about: pages, bookmarks) and `e.web.page` (the engine). `browser [URL]`
// opens URL (default about:blank). The profile (bookmarks and visit log) is `neper-browser.profile` in the working directory,
// read at start and written on exit.
use e.fs
use e.gfx.paint
use e.gpu
use e.io
use e.mem
use e.net.fetch as fetch
use e.net.policy as policy
use e.net.tls.hoststore as hoststore
use e.os
use e.str
use e.text.fontset as fontset
use e.text.shape
use e.time
use e.ui.app
use e.ui.control
use e.ui.html_view as view
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window
use e.web.page as page
use e.web.shell as shell

const MAX_SLOTS: usize = 16usize
const OMNI_BYTES: usize = 1024usize

type FaceSpec = struct { file: str, family: str, weight: u32, italic: bool }
type Slot = struct { model: *Model, index: usize }
type Model = struct {
    a: *mem.Arena, frame: mem.Arena, frame_mark: usize, sh: *shell.Shell, shapes: []shape.Font, tokens: style.ThemeTokens,
    omni: []u8, omni_len: usize, shown_url: str, slots: [16]Slot, labels: [16]str, picks: [16]widget.Submit,
    start_ms: f64, profile_path: str, attached: [16]u32
}

fn url_text(m: *Model) -> str { ret m.omni[0usize..m.omni_len] }

fn set_omni(m: *Model, text: str) {
    var n = text.len
    if n > OMNI_BYTES { n = OMNI_BYTES }
    var i = 0usize
    while i < n {
        m.omni[i] = text[i]
        i += 1usize
    }
    m.omni_len = n
}

fn sync_omni(m: *Model) {
    let t = shell.active_tab(m.sh)
    let u = shell.current_entry(t).url
    if !str.eq(u, m.shown_url) {
        m.shown_url = u
        if str.starts_with(u, "about:blank") { set_omni(m, "") } else { set_omni(m, u) }
    }
}

fn on_omni_change(ctx: *void, text: str) -> err {
    let m = mem.cast[*Model](ctx)
    set_omni(m, text)
    ret ok
}

fn on_omni_submit(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let t = shell.active_tab(m.sh)
    let e = shell.navigate(m.sh, t, url_text(m))
    m.shown_url = ""
    ret ok
}

fn on_back(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let moved = shell.go_back(m.sh, shell.active_tab(m.sh))
    m.shown_url = ""
    ret ok
}

fn on_forward(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let moved = shell.go_forward(m.sh, shell.active_tab(m.sh))
    m.shown_url = ""
    ret ok
}

fn on_reload(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    shell.reload(m.sh, shell.active_tab(m.sh))
    ret ok
}

fn on_new_tab(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let (t, e) = shell.open_tab(m.sh, "about:blank")
    m.shown_url = ""
    ret ok
}

fn on_close_tab(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    if shell.tab_count(m.sh) > 1usize {
        let e = shell.close_tab(m.sh, m.sh.active)
    }
    m.shown_url = ""
    ret ok
}

fn on_bookmark(ctx: *void) -> err {
    let m = mem.cast[*Model](ctx)
    let added = shell.toggle_bookmark(m.sh, shell.active_tab(m.sh))
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let s = mem.cast[*Slot](ctx)
    let e = shell.select_tab(s.model.sh, s.index)
    s.model.shown_url = ""
    ret ok
}

fn submit_of(m: *Model, f: fn(*void) -> err) -> widget.Submit { ret widget.Submit { ctx: mem.cast[*void](m), invoke: f } }

fn now_ms() -> f64 {
    let (t, e) = time.monotonic()
    ret f64(t.nanos) / 1000000.0f64
}

// One frame of page work: timers and scripts, a navigation the page asked for, and a link the view reports as followed.
fn pump_page(m: *Model) {
    let t = shell.active_tab(m.sh)
    if !t.loaded { ret }
    let more = page.tick(t.pg, now_ms() - m.start_ms)
    let moved = shell.follow_pending(m.sh, t)
    let (link, tapped) = view.take_activated(t.pg.view)
    if tapped {
        let (abs, good) = page.resolve_against(m.a, &t.pg.base, link)
        if good {
            let e = shell.navigate(m.sh, t, abs)
            m.shown_url = ""
        }
    }
}

fn build(m: *Model, ctx: *widget.BuildContext) -> (widget.Node, err) {
    mem.reset(&m.frame, m.frame_mark)
    let f = &m.frame
    pump_page(m)
    sync_omni(m)
    let sh = m.sh
    let t = shell.active_tab(sh)
    if t.loaded && m.attached[sh.active] != t.id {
        page.attach_renderer(t.pg, widget.renderer_of(ctx.runtime))
        m.attached[sh.active] = t.id
    }
    let theme = control.Theme { tokens: &m.tokens, fonts: m.shapes, language: "", runtime: ctx.runtime }
    // Tab strip.
    var n = shell.tab_count(sh)
    if n > MAX_SLOTS { n = MAX_SLOTS }
    var i = 0usize
    while i < n {
        m.slots[i] = Slot { model: m, index: i }
        m.picks[i] = widget.Submit { ctx: mem.cast[*void](&m.slots[i]), invoke: on_pick }
        m.labels[i] = shell.tab_title(sh.tabs.items[i])
        i += 1usize
    }
    let (strip, strip_error) = control.tabs(f, 10u64, &theme, m.labels[0usize..n], sh.active, m.picks[0usize..n])
    if strip_error != ok { ret (zero, strip_error) }
    let tab = shell.active_tab(m.sh)
    // Toolbar.
    let back = submit_of(m, on_back)
    let forward = submit_of(m, on_forward)
    let reload_a = submit_of(m, on_reload)
    let newtab = submit_of(m, on_new_tab)
    let closetab = submit_of(m, on_close_tab)
    let mark = submit_of(m, on_bookmark)
    let (bn, be) = mem.alloc[widget.Node](f, 10usize)
    if be != ok { ret (zero, be) }
    var opts = control.button_options()
    opts.enabled = shell.can_go_back(tab)
    let (b1, e1) = control.button(f, 11u64, &theme, "<", &back, opts)
    if e1 != ok { ret (zero, e1) }
    bn[0usize] = b1
    opts.enabled = shell.can_go_forward(tab)
    let (b2, e2) = control.button(f, 12u64, &theme, ">", &forward, opts)
    if e2 != ok { ret (zero, e2) }
    bn[1usize] = b2
    opts.enabled = true
    let (b3, e3) = control.button(f, 13u64, &theme, "Reload", &reload_a, opts)
    if e3 != ok { ret (zero, e3) }
    bn[2usize] = b3
    var fo = control.field_options()
    fo.placeholder = "Search or enter address"
    var field_style = style.defaults()
    field_style.width = style.Length { Flex: 1.0 }
    let (omni_field, oe) = control.text_field(f, 14u64, &theme, "Address", m.omni, m.omni_len, widget.Change[str] { ctx: mem.cast[*void](m), invoke: on_omni_change }, submit_of(m, on_omni_submit), fo)
    if oe != ok { ret (zero, oe) }
    let (wrap_nodes, we) = mem.alloc[widget.Node](f, 1usize)
    if we != ok { ret (zero, we) }
    wrap_nodes[0usize] = omni_field
    bn[3usize] = widget.box(15u64, field_style, wrap_nodes[0usize..1usize])
    var star = "Star"
    if shell.is_bookmarked(m.sh, tab) { star = "Starred" }
    let (b4, e4) = control.button(f, 16u64, &theme, star, &mark, opts)
    if e4 != ok { ret (zero, e4) }
    bn[4usize] = b4
    let (b5, e5) = control.button(f, 17u64, &theme, "+", &newtab, opts)
    if e5 != ok { ret (zero, e5) }
    bn[5usize] = b5
    opts.enabled = shell.tab_count(m.sh) > 1usize
    let (b6, e6) = control.button(f, 18u64, &theme, "x", &closetab, opts)
    if e6 != ok { ret (zero, e6) }
    bn[6usize] = b6
    var toolbar_style = style.defaults()
    toolbar_style.width = style.Length { Percent: 100.0 }
    let toolbar = widget.flex(19u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 6.0 }, toolbar_style, bn[0usize..7usize])
    // The page.
    var content_style = style.defaults()
    content_style.width = style.Length { Percent: 100.0 }
    content_style.height = style.Length { Flex: 1.0 }
    var content: widget.Node = zero
    if tab.loaded {
        let (inner, ie) = mem.alloc[widget.Node](f, 1usize)
        if ie != ok { ret (zero, ie) }
        inner[0usize] = widget.Node { key: 21u64, kind: widget.Kind { Custom: view.custom(tab.pg.view) }, style: content_style, children: zero }
        content = widget.region(20u64, view.region(tab.pg.view), content_style, inner[0usize..1usize])
    } else {
        content = widget.box(20u64, content_style, zero)
    }
    let (rows, re) = mem.alloc[widget.Node](f, 3usize)
    if re != ok { ret (zero, re) }
    rows[0usize] = strip
    rows[1usize] = toolbar
    rows[2usize] = content
    var root_style = style.defaults()
    root_style.width = style.Length { Percent: 100.0 }
    root_style.height = style.Length { Percent: 100.0 }
    root_style.background = paint.Brush { Solid: paint.rgba(0.96, 0.96, 0.97, 1.0) }
    ret (widget.flex(1u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 4.0 }, root_style, rows[0usize..3usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Fonts for the page and for the chrome.
    let (made, made_error) = fontset.new(a)
    if made_error != ok { os.exit(3i32) }
    var fonts = made
    let faces = [8]FaceSpec { FaceSpec { file: "C:/Windows/Fonts/segoeui.ttf", family: "Segoe UI", weight: 400u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/segoeuib.ttf", family: "Segoe UI", weight: 700u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/arial.ttf", family: "Arial", weight: 400u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/arialbd.ttf", family: "Arial", weight: 700u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/ariali.ttf", family: "Arial", weight: 400u32, italic: true }, FaceSpec { file: "C:/Windows/Fonts/times.ttf", family: "Times New Roman", weight: 400u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/cour.ttf", family: "Courier New", weight: 400u32, italic: false }, FaceSpec { file: "C:/Windows/Fonts/verdana.ttf", family: "Verdana", weight: 400u32, italic: false } }
    var added = 0usize
    var fi = 0usize
    while fi < 8usize {
        let (bytes, fe) = fs.read_file(a, faces[fi].file, 33554432usize)
        if fe == ok && fontset.add(&fonts, faces[fi].family, faces[fi].weight, faces[fi].italic, bytes, 0u32) == ok { added += 1usize }
        fi += 1usize
    }
    if added == 0usize { os.exit(4i32) }
    fontset.set_generic(&fonts, "sans-serif", "Arial")
    fontset.set_generic(&fonts, "serif", "Times New Roman")
    fontset.set_generic(&fonts, "monospace", "Courier New")
    fontset.set_generic(&fonts, "system-ui", "Segoe UI")
    let (shapes, shapes_error) = mem.alloc[shape.Font](a, fonts.faces.len + 1usize)
    if shapes_error != ok { os.exit(5i32) }
    var si = 0usize
    while si < fonts.faces.len {
        shapes[si] = fonts.faces.items[si].font
        si += 1usize
    }
    // Network.
    let (roots, roots_error) = hoststore.system_roots(a, 4194304usize)
    if roots_error != ok { os.exit(6i32) }
    var net_config = fetch.default_config(roots.der)
    // An Adblock Plus list in `neper-browser.filters` (optional) names hosts no page may load from.
    let (filter_text, filter_error) = fs.read_file(a, "neper-browser.filters", 33554432usize)
    if filter_error == ok { 
        let rules = policy.parse_filter_list(a, filter_text)
        net_config.block_hosts = rules.domains
        net_config.allow_hosts = rules.allow
        net_config.third_hosts = rules.third
    }
    let (cl, client_error) = fetch.client(a, net_config, 256usize)
    if client_error != ok { os.exit(7i32) }
    var client = cl
    // The shell, its profile and the first tab.
    let (sh, shell_error) = shell.new(a, &client, &fonts, 1100.0f32, 700.0f32)
    if shell_error != ok { os.exit(8i32) }
    let profile_path = "neper-browser.profile"
    let loaded_profile = shell.load_profile(sh, profile_path)
    var first = "about:blank"
    if args.len > 1usize { first = args[1usize] }
    let (t0, open_error) = shell.open_tab(sh, first)
    if open_error != ok { os.exit(9i32) }
    // The window.
    let (omni, omni_error) = mem.alloc[u8](a, OMNI_BYTES)
    if omni_error != ok { os.exit(10i32) }
    let (frame_storage, fs_error) = mem.alloc[u8](a, 4194304usize)
    if fs_error != ok { os.exit(11i32) }
    let (mstore, mstore_error) = mem.alloc[Model](a, 1usize)
    if mstore_error != ok { os.exit(12i32) }
    let model = &mstore[0usize]
    model.a = a
    model.frame = mem.arena_from(frame_storage)
    model.frame_mark = mem.mark(&model.frame)
    model.sh = sh
    model.shapes = shapes[0usize..fonts.faces.len]
    model.tokens = style.reference(.Light)
    model.omni = omni
    model.omni_len = 0usize
    model.shown_url = ""
    model.start_ms = now_ms()
    model.profile_path = profile_path
    var ai = 0usize
    while ai < MAX_SLOTS {
        model.attached[ai] = 0u32
        ai += 1usize
    }
    let options = app.Options {
        window: window.Options { title: "Neper", width: 1100u32, height: 700u32, min_width: 400u32, min_height: 300u32, resizable: true, transparent: false, mode: .Windowed },
        widget_limits: widget.Limits { max_elements: 4096usize, max_states: 256usize, state_bytes: 1024usize, state_classes: 16u16, max_depth: 48u16, max_commands: 65536usize },
        frame_arena_bytes: 16777216usize,
        event_capacity: 256usize,
        backend: .Cpu,
    }
    let (application, init_error) = app.init[Model](a, options, app.Builder[Model] { ctx: model, build: build })
    if init_error == app.Failed {
        let p = io.print("this host has no windows\n")
        ret ok
    }
    if init_error != ok { os.exit(13i32) }
    var running = application
    var go = true
    while go {
        let (more, step_error) = app.step(&running, time.millis(16i64))
        if step_error != ok || !more { go = false }
    }
    let saved = shell.save_profile(sh, profile_path)
    let closed = app.close(&running)
    ret ok
}

