// `e.ui.browser` (browser tracker 7.1, 7.2): one browsing context as an `e.ui` control. It is the windowed layer over
// `e.web.shell` (session history, the omnibox rules, error pages) and `e.web.page` (fetch, parse, style, layout, paint,
// scripts): `attach` binds the control to a shell tab, `pump` is the tab's frame of work (timers, a navigation the
// scripts asked for, a tap reaching the page and then its link), `state` is what a caller's chrome reads, and `canvas`
// / `region` are the widgets it composes into its own tree. Chrome (tabs, omnibox, bookmarks, downloads) is not here.
//
// The control keeps no state of its own: a `Browser` is two pointers, so a caller may make one wherever it needs it (a
// frame, an event handler) and never has to keep it in step with a tab. The page and its history live in the tab,
// which is what lets a reload, a back or a forward replace the page without the caller re-binding anything.
use e.gfx.scene as scene
use e.mem
use e.str
use e.ui.accessibility
use e.ui.html_view as view
use e.ui.widget
use e.web.page as page
use e.web.shell as shell

// What the caller's chrome shows: the address, the page's title, whether a page is loaded, why it failed, and whether
// the tab's session history has an entry in each direction.
type State = struct { url: str, title: str, ready: bool, error_text: str, can_back: bool, can_forward: bool }

type Browser = struct { sh: *shell.Shell, tab: *shell.Tab }

// Binds the control to a shell tab; the same tab gives the same browsing context.
fn attach(sh: *shell.Shell, t: *shell.Tab) -> Browser {
    ret Browser { sh: sh, tab: t }
}

fn has_page(b: *const Browser) -> bool { ret b.tab.loaded }

fn state(b: *const Browser) -> State {
    let t = b.tab
    ret State {
        url: shell.current_entry(t).url,
        title: shell.tab_title(t),
        ready: t.loaded,
        error_text: t.error_text,
        can_back: shell.can_go_back(t),
        can_forward: shell.can_go_forward(t)
    }
}

// Navigates to what the omnibox makes of `input` (an address, a host name, or a search for the text). A load that
// fails leaves the error page, so `state().error` says why while `ready` stays true.
fn navigate(b: *Browser, input: str) -> err {
    ret shell.navigate(b.sh, b.tab, input)
}

// Moves through the tab's session history; false when there is no entry in that direction.
fn back(b: *Browser) -> bool {
    ret shell.go_back(b.sh, b.tab)
}

fn forward(b: *Browser) -> bool {
    ret shell.go_forward(b.sh, b.tab)
}

// Loads the current entry again into the tab's arena, which gives the tab a new page object.
fn reload(b: *Browser) {
    shell.reload(b.sh, b.tab)
}

// The host's media preferences for every page of this browser: `dark` answers `prefers-color-scheme` (and
// `light-dark()`), `reduced_motion` answers `prefers-reduced-motion`. A page whose answer changes is laid out again,
// so the next frame paints it; a page loaded later is laid out with them from the start.
fn set_preferences(b: *Browser, dark: bool, reduced_motion: bool) {
    shell.set_preferences(b.sh, dark, reduced_motion)
}

// Binds the page's images and web fonts to the frame's renderer. Meant to be called every frame: a page loaded since
// the last one (reload, back, forward, a link) has no renderer yet, and an unchanged one costs two field reads.
fn ensure_renderer(b: *Browser, r: *scene.Renderer) {
    let t = b.tab
    if !t.loaded { ret }
    if t.pg.has_renderer && mem.address_of(t.pg.renderer) == mem.address_of(r) { ret }
    page.attach_renderer(t.pg, r)
}

// One frame of the tab's work: timers and promise jobs, a navigation its scripts asked for, a tap that reaches the
// page's click handlers, and a link tap those handlers did not cancel. True when the page changed and must be painted.
fn pump(b: *Browser, now_ms: f64) -> bool {
    let t = b.tab
    if !t.loaded { ret false }
    var changed = page.tick(t.pg, now_ms)
    if shell.follow_pending(b.sh, t) { changed = true }
    let (tx, ty, tapped) = view.take_tap(t.pg.view)
    var allowed = true
    if tapped { allowed = page.click(t.pg, tx, ty) }
    let (link, hit) = view.take_activated(t.pg.view)
    if hit && allowed {
        let (abs, good) = page.resolve_against(b.sh.a, &t.pg.base, link)
        if good {
            if shell.navigate(b.sh, t, abs) == ok { changed = true }
        }
    }
    ret changed
}

// Whether a timer is due by `now_ms`, the same clock `pump` is given: an idle window asks for no frame, so a timer
// minutes away costs nothing while the caller still wakes for one that is due.
fn timer_due(b: *const Browser, now_ms: f64) -> bool {
    if !b.tab.loaded { ret false }
    let due = page.next_wakeup(b.tab.pg)
    ret due >= 0.0f64 && due <= now_ms
}

// The page's canvas: wrap it in `region` and put both in the caller's tree. A tab with no page has an empty canvas,
// where the caller draws its own start page.
fn canvas(b: *Browser) -> widget.Custom {
    if !b.tab.loaded { ret zero }
    ret view.custom(b.tab.pg.view)
}

// Wheel scrolling, taps (links) and hover over the canvas.
fn region(b: *Browser) -> widget.Region {
    if !b.tab.loaded { ret zero }
    ret view.region(b.tab.pg.view)
}

// --- Accessibility -----------------------------------------------------------------------------------------------------
//
// The page's document tree as an `e.ui.accessibility` tree, for a host that publishes or inspects it. The roles and
// names come from `e.fmt.html.accessible` by way of `e.ui.html_view.a11y`; `semantics` is what puts the same tree into
// the widget tree under the canvas, so `e.ui.app` publishes it when a screen reader is listening. Bounds, actions,
// relations and live regions are not filled yet.

// The page's accessibility tree on its own; a tab with no page answers an empty tree.
fn a11y_tree(b: *Browser, a: *mem.Arena) -> (accessibility.Tree, err) {
    var empty = accessibility.Tree { root: zero, nodes: zero }
    if !b.tab.loaded { ret (empty, ok) }
    let (content, content_error) = view.a11y(b.tab.pg.view, a)
    if content_error != ok { ret (empty, content_error) }
    let (tree, tree_error) = accessibility.content_tree(a, &content)
    ret (tree, tree_error)
}

// The semantics that carries the page's content into the widget tree: the caller wraps `canvas(b)` in
// `widget.semantics(key, semantics(b), style, [the canvas])`.
fn semantics(b: *Browser) -> widget.Semantics {
    if !b.tab.loaded { ret zero }
    ret view.semantics(b.tab.pg.view)
}
