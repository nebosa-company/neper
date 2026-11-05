# Handover: the browser control (`e.ui.browser`) — 2026-11-05

The one handover for the browser **control** (browser tracker rows 7.0–7.6, `docs/browser-progress.html`). The
engine/conformance stream is `docs/HANDOVER-BROWSER.md` — a different programme, different owner. The control is
the `e.ui` layer: one browsing context as a widget the shell and other apps embed.

## What exists now

- `lib/e/ui/browser.e` — the control, stateless (`Browser` is two pointers: shell + tab). API:
  `attach`, `navigate/back/forward/reload`, `state` (url, title, ready, error_text, can_back/forward), `pump`
  (timers, script-requested navigation, tap → page click → link), `timer_due`, `ensure_renderer` (binds each page
  object once), `canvas`, `region`, `keys`, `semantics`, `a11y_tree`, `set_preferences`.
- `examples/browser/main.e` — chrome only now (tabs, omnibox, bookmarks, profile) over the control. Its page area is
  nested `scope > region > semantics > canvas`: the scope carries the scroll keys, the focusable region gives the page
  the keyboard, the semantics carries the document's accessibility tree.
- `lib/e/ui/html_view.e` — added: focusable region, `keys`/`key_scroll` (arrows 40 px, PageUp/PageDown/Space a
  viewport, Home/End, Shift+Space back), `a11y`/`semantics` (document tree as `widget.A11yTree`), `set_preferences`.
- `lib/e/ui/widget.e` + `lib/e/ui/accessibility.e` — `Semantics.content` provider (`A11y`, `A11yTree`, `A11yNode`);
  `accessibility.build` splices a canvas's content nodes under its element; `fill_content`/`content_tree` convert.
- `lib/e/web/shell.e` + `page.e` — `dark`/`reduced_motion` kept on the shell (pages loaded later start with them) and
  applied to pages; `page.set_preferences` re-styles and re-lays out.
- Fixture `tests/selfhost/fixtures/link/ui_browser`, registered in `run.ps1` and `run.sh`.

## Commits that landed this session (on `origin/master`)

`68124c66a` control extracted from the app · `12936a42c` media preferences · `3cba20b4e` page accessibility tree ·
`daa4a0a8d` content provider spliced into the widget tree · `02ace183b` layout boxes + press action · `2adfaf971`
keyboard scrolling.

## Build and check

    # app (needs a big-arena compiler: neper-try exhausts its own arena, neper-browser-win hung after writing)
    build/windows/neper-big.exe emit-executable examples/browser/main.e . x64 windows build/windows/browser-ui.exe

    # the control's fixture
    build/windows/neper-try.exe emit-executable tests/selfhost/fixtures/link/ui_browser/src/main.e . x64 windows build/windows/ui_browser_check.exe
    build/windows/ui_browser_check.exe

Regressions worth rerunning after touching `widget`, `accessibility` or `html_view`: `ui_accessibility`, `ui_scroll`,
`ui_gesture`, `ui_app` (all passed at handover). Python for the doc generators: `D:\tools\neper-pyenv\Scripts\python.exe`
— `D:\tools\python312\python.exe` is sealed by a `python312._pth` and cannot import the sibling scripts.

## Traps this session hit (do not re-learn)

1. `scene.renderer(a, device, q, max_scenes, max_textures)`: every `scene.compile` consumes a scene slot. A fixture
   that compiles N scenes needs `max_scenes > N`; three compiles with `max_scenes: 2` fail in `widget.reconcile` as
   `TooLarge`, which reads like a layout bug.
2. Neper has no direct tuple `ret f()`: returns `(t, e)` from a call are `E-TYPE-0003`; bind then `ret (t, e)`.
3. D66: a parameter cannot reuse a module qualifier. `fn navigate(b, input)` broke the moment `use e.ui.input` arrived;
   the parameter is `address` now, and the fence matches.
4. Struct literals must list every field. Adding one to `widget.Custom` costs ~100 call sites, which is why the
   accessibility provider lives on `Semantics` (everywhere constructed `var s: Semantics = zero` + fields).
5. `html_view`'s region is focusable now: a tap focuses the document and an ancestor scope receives the keys. This
   changes Mail/Document views too — intended, but it is a behaviour change.
6. A page's document, styles and layout live in the page's own arena; accessibility and content trees allocate in the
   arena the caller passes to `accessibility.build`.

## Open, with the decision that comes first

- **7.3 focus and tab order into the page** (links/controls in Tab order, a focus ring, scroll-into-view, Enter
  activation). Needs a host → document focus path; there is none today (`dom_js` owns JS-side `focus()`, `page` and
  `script` expose no hook). Options: (a) the control runs a small script snippet; (b) add `page.focus_node` that
  `dom_js` honours — needs the DOM owner; (c) visual focus only until (b). Recommend (b), agreed with the DOM stream.
- 7.3 also owes text input via `Edit` + IME, clipboard, kinetic scroll, scrollbars, cursor.
- 7.6 owes relations and live regions (`e.fmt.html.accessible` exposes neither) and the OS preference source (L229).
- The `scope > region > semantics > canvas` nesting is compile-verified only; nobody has looked at a window (no GUI in
  that environment). Check it when the app next runs.
