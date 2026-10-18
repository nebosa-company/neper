// `e.ui.html_view` (tracker 3.3, M1): a static HTML/CSS page as an `e.ui` widget. `open` parses a document, resolves
// its style (the user agent sheet, the caller's author sheets in cascade order, then the document's own `<style>`
// elements) and lays it out against the fonts of an `e.text.fontset`; `custom` is the canvas that paints the visible part
// into the widget scene (`e.fmt.css.paint`), `region` the wheel scrolling and link taps over it. Nothing is executed or
// fetched: images come from the host's `Images` callbacks, links are reported through `activated`, never followed.
//
// The view keeps its scroll offset; the layout is redone when the canvas gets a different size. Bump of `revision`
// (scroll, resize, load) is the canvas state, so an unchanged frame replays its last paint.
//
// Memory: `open` allocates the document, styles and layout in the arena it is given and keeps one frame mark after
// them: every paint, and every relayout, first rewinds the arena to its mark, so the arena must not be used by
// anything else after `open` returns (give the view its own arena).

use e.fmt.css.geom as geom
use e.fmt.css.layout as layout
use e.fmt.css.measure as measure
use e.fmt.css.paint as css_paint
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.html as html
use e.gfx.geometry as geometry
use e.gfx.scene as scene
use e.mem
use e.str
use e.text.fontset as fontset
use e.ui.layout as ui_layout
use e.ui.widget

// Host callbacks for replaced content; `intrinsic` sizes an element (layout), `image` supplies its texture (paint).
type Images = struct {
    ctx: *void,
    intrinsic: fn(*void, html.NodeId, *const style.Style) -> layout.Intrinsic,
    image: fn(*void, html.NodeId) -> css_paint.ImageRef,
    url_image: fn(*void, str) -> css_paint.ImageRef
}

type View = struct {
    arena: *mem.Arena, fonts: *fontset.Set, source: str, sheets: []const str,
    complete_sheets: bool, tree: dom.Dom, styles: []style.Style, lay: layout.Layout, host: measure.Host,
    width: f32, height: f32, scroll_x: f32, scroll_y: f32, origin_x: f32, origin_y: f32,
    revision: u64, layout_mark: usize, frame_mark: usize,
    activated: str, has_activated: bool, hover_link: str, has_hover: bool, opened: bool
}

error EmptyFontSet

fn none_intrinsic(ctx: *void, node: html.NodeId, s: *const style.Style) -> layout.Intrinsic { ret zero }

fn none_image(ctx: *void, node: html.NodeId) -> css_paint.ImageRef { ret zero }

// No pictures: replaced elements get the 300x150 default and paint nothing.
fn none_url_image(ctx: *void, url: str) -> css_paint.ImageRef { ret zero }

fn no_images() -> Images {
    ret Images { ctx: zero, intrinsic: none_intrinsic, image: none_image, url_image: none_url_image }
}

fn parse_options() -> html.Options {
    ret html.Options { max_bytes: 16777216usize, max_nodes: 400000usize, max_attributes: 256usize, max_depth: 512u16, preserve_comments: false }
}

fn do_layout(v: *View, width: f32, height: f32) -> err {
    mem.reset(v.arena, v.layout_mark)
    var ctx = style.new_context(v.arena, f64(width), f64(height))
    // `ch` and `ex` follow the default font: the advance of its `0` and its x-height.
    let m0 = measure.measure_of(&v.host)
    var probe = style.initial_style()
    probe.font_size = 16.0f64
    let zero_w = m0.width(m0.ctx, &probe, "0")
    if zero_w > 0.0f64 { ctx.ch = zero_w / 16.0f64 }
    let probe_fm = m0.metrics(m0.ctx, &probe)
    if probe_fm.x_height > 0.0f64 { ctx.ex = probe_fm.x_height / 16.0f64 }
    let (styles, se) = mem.alloc[style.Style](v.arena, v.tree.used)
    if se != ok { ret se }
    v.styles = styles
    if v.complete_sheets { try style.compute_document_sheets(&ctx, &v.tree, v.sheets, v.styles) } else { try style.compute_document(&ctx, &v.tree, v.sheets, v.styles) }
    let m = measure.measure_of(&v.host)
    let (lay, le) = layout.layout_document(v.arena, &v.tree, v.styles, m, f64(width), f64(height))
    if le != ok { ret le }
    v.lay = lay
    v.width = width
    v.height = height
    v.frame_mark = mem.mark(v.arena)
    v.revision += 1u64
    ret ok
}

// The document height in pixels (at least the viewport's).
fn document_height(v: *const View) -> f32 { ret f32(v.lay.doc_height) }

fn clamp_scroll(v: *View) {
    let limit_y = document_height(v) - v.height
    if v.scroll_y > limit_y { v.scroll_y = limit_y }
    if v.scroll_y < 0.0 { v.scroll_y = 0.0 }
    let limit_x = f32(v.lay.doc_width) - v.width
    if v.scroll_x > limit_x { v.scroll_x = limit_x }
    if v.scroll_x < 0.0 { v.scroll_x = 0.0 }
}

// Parses `source`, styles and lays it out for a `width` x `height` viewport. `sheets` are author style sheets as text
// in cascade order (fetched `<link>`s); `fonts` must hold at least one face and outlive the view.
fn open(a: *mem.Arena, source: str, sheets: []const str, fonts: *fontset.Set, images: Images, width: f32, height: f32) -> (*View, err) {
    let (tree, pe) = dom.parse(a, source, parse_options(), 1024usize)
    if pe != ok { ret (zero, pe) }
    let (v, e) = open_tree(a, tree, source, sheets, false, fonts, images, width, height)
    ret (v, e)
}

// As `open`, for a document already parsed. With `complete_sheets` the `sheets` hold every style sheet in document order
// (the `<style>` elements are not read again).
fn open_tree(a: *mem.Arena, tree: dom.Dom, source: str, sheets: []const str, complete: bool, fonts: *fontset.Set, images: Images, width: f32, height: f32) -> (*View, err) {
    if fonts.faces.len == 0usize { ret (zero, EmptyFontSet) }
    let (cell, ce) = mem.alloc[View](a, 1usize)
    if ce != ok { ret (zero, ce) }
    let v = &cell[0usize]
    v.complete_sheets = complete
    v.arena = a
    v.fonts = fonts
    v.source = source
    v.sheets = sheets
    v.tree = tree
    v.host = measure.Host { fonts: fonts, arena: a, ctx: images.ctx, intrinsic: images.intrinsic, image: images.image, url_image: images.url_image }
    v.scroll_x = 0.0
    v.scroll_y = 0.0
    v.revision = 1u64
    v.has_activated = false
    v.has_hover = false
    v.layout_mark = mem.mark(a)
    v.frame_mark = mem.mark(a)
    try do_layout(v, width, height)
    v.opened = true
    ret (v, ok)
}

// Lays the page out again for another viewport size, keeping the scroll position within the new bounds.
fn resize(v: *View, width: f32, height: f32) -> err {
    try do_layout(v, width, height)
    clamp_scroll(v)
    ret ok
}

fn scroll_to(v: *View, x: f32, y: f32) {
    let ox = v.scroll_x
    let oy = v.scroll_y
    v.scroll_x = x
    v.scroll_y = y
    clamp_scroll(v)
    if v.scroll_x != ox || v.scroll_y != oy { v.revision += 1u64 }
}

fn scroll_by(v: *View, dx: f32, dy: f32) {
    scroll_to(v, v.scroll_x + dx, v.scroll_y + dy)
}

// --- Links.

// The `href` of the link under a viewport point, if any.
fn link_at(v: *View, x: f32, y: f32) -> (str, bool) {
    let hit = geom.hit_test(v.arena, &v.lay, v.lay.root, f64(x + v.scroll_x), f64(y + v.scroll_y))
    if hit == layout.NONE { ret ("", false) }
    var node = v.lay.boxes.items[usize(hit)].node
    while node != html.NONE {
        let n = &v.tree.nodes[usize(node)]
        if n.kind == .Element && str.eq(n.name, "a") {
            let (href, has) = dom.get_attribute(&v.tree, node, "href")
            if has { ret (href, true) }
        }
        node = n.parent
    }
    ret ("", false)
}

// The node under a viewport point, or html.NONE.
fn node_at(v: *View, x: f32, y: f32) -> html.NodeId {
    let hit = geom.hit_test(v.arena, &v.lay, v.lay.root, f64(x + v.scroll_x), f64(y + v.scroll_y))
    if hit == layout.NONE { ret html.NONE }
    ret v.lay.boxes.items[usize(hit)].node
}

// --- The widget.

fn measure_view(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    let v = mem.cast[*View](ctx)
    var w = limits.max_width
    var h = limits.max_height
    if !(w < 100000000.0) { w = v.width }
    if !(h < 100000000.0) { h = v.height }
    ret geometry.Size { width: w, height: h }
}

fn paint_view(ctx: *void, builder: *scene.Builder, area: geometry.Rect) -> err {
    let v = mem.cast[*View](ctx)
    if area.width <= 0.0 || area.height <= 0.0 { ret ok }
    if area.width != v.width || area.height != v.height { try resize(v, area.width, area.height) }
    v.origin_x = area.x
    v.origin_y = area.y
    mem.reset(v.arena, v.frame_mark)
    let save: scene.Command = .Save
    let restore: scene.Command = .Restore
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Transform: geometry.transform_translate(area.x, area.y) })
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 0.0, area.width, area.height) } })
    let env = measure.paint_env_of(&v.host)
    try css_paint.paint(v.arena, &v.lay, env, builder, geometry.rect(v.scroll_x, v.scroll_y, area.width, area.height), f64(v.scroll_x), f64(v.scroll_y))
    try scene.push(builder, restore)
    ret ok
}

// The canvas; the view must outlive the widget tree that refers to it.
fn custom(v: *View) -> widget.Custom {
    ret widget.Custom { ctx: mem.cast[*void](v), measure: measure_view, paint: paint_view, state: widget.bytes_of[u64](&v.revision) }
}

// Notches of the mouse wheel scroll this many pixels.
fn wheel_step() -> f32 { ret 48.0 }

fn gesture_view(ctx: *void, g: widget.Gesture) -> err {
    let v = mem.cast[*View](ctx)
    switch g {
    case .Wheel as w:
        scroll_by(v, 0.0, 0.0 - w.notches * wheel_step())
    case .Tap as p:
        let (href, has) = link_at(v, p.x - v.origin_x, p.y - v.origin_y)
        if has {
            v.activated = href
            v.has_activated = true
        }
    case .Hover as p:
        let (href, has) = link_at(v, p.x - v.origin_x, p.y - v.origin_y)
        v.hover_link = href
        v.has_hover = has
    case .HoverEnd:
        v.has_hover = false
    default:
        ret ok
    }
    ret ok
}

// Wheel scrolling, taps (links) and hover over the canvas: wrap it in `widget.region(key, region(v), style, canvas)`.
fn region(v: *View) -> widget.Region {
    ret widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](v), invoke: gesture_view }, gestures: widget.GESTURE_TAP | widget.GESTURE_HOVER | widget.GESTURE_WHEEL, enabled: true, focusable: false }
}

// The link the last tap activated (cleared by reading it).
fn take_activated(v: *View) -> (str, bool) {
    if !v.has_activated { ret ("", false) }
    v.has_activated = false
    ret (v.activated, true)
}
