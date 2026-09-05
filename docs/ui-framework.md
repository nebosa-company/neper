# Neper declarative GPU UI framework

Status: experimental architecture proposal. The exact public declarations live in
[`module-apis.md`](module-apis.md); module identities, tiers, dependency edges and
blockers live in [`modules.json`](modules.json).

## 1. Goal and boundary

The framework builds portable desktop applications from declarative Neper values and
renders them through `e.gpu`. It borrows Flutter's useful separation between
immutable widget descriptions, persistent elements and render state without copying
its managed-object runtime.

Version 1 targets native desktop windows on Windows, Linux and macOS. It provides:

- immutable widget trees written as ordinary Neper expressions;
- keyed reconciliation and explicit persistent state;
- constraint-based flex, grid, stack and scrolling layout;
- shaped international text, vector drawing, images and GPU composition;
- ordered pointer, keyboard, focus, text-input and IME events;
- an accessibility semantics tree;
- manifest-declared embedded assets with deterministic scale, theme and locale variants;
- deterministic animation and headless widget/snapshot testing.

It does not add language syntax, inheritance, runtime reflection, CSS, JavaScript, a
browser DOM, web-page rendering, a tracing garbage collector or hidden unbounded
allocation. Mobile, browser and embedded targets require separate proposals because
their lifecycle and presentation contracts differ materially from desktop.

## 2. Architecture

```text
application build function
        |
        v
frame-local immutable ui.widget.Node tree
        |
        v
key/kind reconciliation ----> persistent Element + typed State slots
        |                                  |
        v                                  v
constraint layout <--------------- invalidation/focus/actions
        |
        v
retained render tree -> gfx.scene.DisplayList -> tessellation/glyph cache
        |                                      |
        +-------------------------------> e.gpu queue
                                                |
                                                v
                                      native presentation target
```

Three lifetimes are deliberately distinct:

1. **Frame:** widget nodes, child slices and build-time strings occupy a bounded
   frame arena. The arena resets only after reconciliation and scene compilation.
2. **Runtime:** elements, state, focus, scroll offsets and retained render data occupy
   bounded generation-checked slots and size/alignment state cells in the
   application's arena. Retired cells return to bounded per-layout free lists.
3. **GPU:** textures, glyph atlases, meshes and compiled scenes are resources owned
   by `gfx.scene.Renderer` and explicitly released or closed.

No persistent layer stores a pointer into the frame arena. Debug builds poison the
reset frame range, making violations visible under the existing arena rules.

### Embedded assets

`project.yaml` declares immutable assets that the linker places in the executable.
`e.asset` exposes allocation-free lookup by logical name; its strings, metadata and
bytes remain valid for the process lifetime and require no filesystem at runtime.
Every input path, byte size and SHA-256 is recorded in the canonical build manifest.

`ui.asset` groups physical entries by their `base` attribute and deterministically
selects locale, theme and display-scale variants. Fonts become zero-copy
`text.shape.Font` values. Images use a caller-supplied decoder so PNG, JPEG or a
project-specific format remains a separate concern; decoded pixels occupy a caller
scratch arena and are uploaded before it resets. A caller-sized cache owns the GPU
textures and explicitly evicts or releases them. There is no global asset manager.

```neper
use ui.asset as ui_asset

let request = ui_asset.Request{
    scale: window_metrics.scale,
    locale: "es-ES",
    theme: .Dark,
}
let logo = try ui_asset.texture(&cache, scratch, "images/logo", request, png_decoder)
let font = try ui_asset.font("fonts/inter", request, 0)
```

## 3. Declarative code

Declarative UI is a library convention expressed with literals and functions, not a
new grammar form. A helper can return a complete value tree:

```neper
use e.mem
use gfx.paint
use text.layout as text_layout
use ui.input
use ui.layout as ui_layout
use ui.style
use ui.widget

type Counter = struct { value: i64 }

fn counter_action(ctx: *void, event: input.Event) -> err {
    let _ = event
    let counter = mem.cast[*Counter](ctx)
    counter.value = counter.value + 1
    ret ok
}

fn counter_view(counter: *Counter, label_style: text_layout.Style) -> widget.Node {
    let title = widget.Node{
        key: 1,
        kind: widget.Kind{ Text: widget.Text{
            value: "Count",
            style: label_style,
            color: paint.srgb8(20, 20, 20, 255),
        } },
        style: style.defaults(),
        children: nil,
    }
    let button = widget.Node{
        key: 2,
        kind: widget.Kind{ Button: widget.Button{
            action: widget.Action{ ctx: counter, invoke: counter_action },
            enabled: true,
        } },
        style: style.defaults(),
        children: nil,
    }
    ret widget.Node{
        key: 10,
        kind: widget.Kind{ Flex: ui_layout.Flex{ axis: .Vertical, main: .Start, cross: .Center, gap: 8.0 } },
        style: style.defaults(),
        children: [_]widget.Node{ title, button },
    }
}
```

The example uses explicit callback context because Neper has no closures. Higher-level
helpers may reduce literal noise, but their result remains the same `Node` value and
must not create hidden state.

## 4. Reconciliation and state

Within one parent, a nonzero `widget.Key` must be unique. Reconciliation matches a
new child to an old element by `(key, kind)` when the key is nonzero and by
`(position, kind)` otherwise. A duplicate key is `DuplicateKey`. A kind change
replaces the element and retires its state generation.

`widget.state[T]` associates `(element, local key)` with one concrete type. Reusing
the pair with another type returns `StateType`. The returned pointer is stable until
that state is removed or the runtime closes, but application code must not retain it
after either boundary. Removing an element recursively invalidates its state,
captured pointers, focus and pending actions before its slot can be reused. State
cells are recycled only for the same size/alignment class; `state_bytes` and
`state_classes` bound both storage and fragmentation. Values that own external
resources require an explicit application cleanup action because Neper has no
destructors.

An `Action.ctx` retained by an element must remain valid until that element is
reconciled away. It may point to application state or `widget.state` storage, never
to the frame arena. Strings and slices needed after reconciliation are copied into
bounded runtime storage or compiled into the retained render/semantics data; no
persistent structure borrows a widget node.

Rebuild is explicit invalidation. Dispatching an action may mutate application or
widget state and call `widget.invalidate`; `ui.animation.request` schedules another
frame. There is no observation graph, implicit setter interception or global event
bus.

## 5. Layout, paint and text

Layout uses Flutter-like downward constraints and upward sizes. Parents then assign
child positions. Every constraint and result is finite and non-negative; invalid or
contradictory limits return `Invalid`. Flex and grid distribute only bounded
remaining space, with deterministic sibling-order rounding.

Painting emits a backend-neutral display list. Save/restore scopes transforms and
clips; malformed nesting is `Invalid`. `gfx.scene` validates the whole list before
submitting GPU work, tessellates paths, maintains bounded generation-checked texture
and glyph caches, and rebuilds resources after a recoverable presentation change.
Device loss remains `Lost` and is never silently hidden.

Text follows this pipeline:

```text
UTF-8 + style
  -> Unicode bidi/script segmentation and font fallback
  -> OpenType glyph shaping
  -> line breaking, alignment and caret geometry
  -> glyph atlas entries and display-list commands
```

Fonts are caller-provided byte slices. Platform font discovery is intentionally not
part of the pure shaping modules; a later host service may enumerate fonts through a
reviewed `e.os` primitive. This keeps tests reproducible and prevents hidden file I/O.

## 6. Input, frames and accessibility

`ui.input.Queue` preserves native event order. Pointer coordinates are logical
pixels. Pointer capture, keyboard focus and IME composition are explicit. Dispatch
performs hit testing from the last committed render tree, then runs capture and
bubble phases internally; version 1 exposes one action at the target rather than a
mutable event-object hierarchy. A close request is data—the application decides when
to close the window.

`ui.app.step` is the scheduling primitive. It waits up to the supplied duration,
drains input, invokes actions, samples time once, rebuilds invalidated subtrees,
reconciles, lays out and presents at most one frame per window. `run` merely repeats
`step`, so games, editors and external event loops keep control.

Accessibility is derived from semantic widget properties and published as a separate
stable-ID tree. Paint-only decorations do not appear. Platform requests such as
focus, press or setting a value route back through the same action system. The
framework does not claim accessibility until the native bridge blocker is delivered
and tested with each platform's assistive APIs.

## 7. Platform and GPU prerequisites

The proposal records four blockers instead of weakening the platform-boundary rule:

- `native-window-api`: reviewed `e.os` primitives for windows, monitors, event
  delivery, clipboard, cursor, pointer capture and IME;
- `gpu-presentation-api`: `e.gpu` support for presentation targets, textures, render
  passes, blending, synchronization, resize and device-loss recovery;
- `native-accessibility-api`: reviewed publication and action bridges for Windows,
  Linux and macOS accessibility systems.
- `embedded-asset-linking`: canonical manifest ingestion, incremental hashing,
  read-only executable sections and linker-generated `e.asset` registry symbols.

These primitives must be specified in `spec.md` and added to the exact `e.os` and
`e.gpu` catalogues before the blocked modules can move from proposal to
implementation. UI modules never declare platform `extern`s directly.

## 8. Resource limits and failure

Every runtime is constructed with limits for elements, state entries, depth and
display-list commands. Event queues, texture tables, scene tables, glyph atlases and
frame arenas are also bounded at construction. Exceeding a bound returns `TooLarge`
or `OutOfMemory`; the last presented frame remains valid. Reconciliation either
commits a complete new tree or leaves the previous tree active.

Callbacks return `err`. The framework stops dispatch along the current event,
preserves runtime invariants and returns the error from `step`; it does not throw,
log globally or continue with a partially committed tree. Resource closure is
explicit and logically linear under the language's existing handle rules.

## 9. Testing and delivery

The first useful vertical slice is deliberately narrower than the full catalogue:

1. CPU reference renderer, geometry, solid paint and deterministic snapshots;
2. synthetic window/input, box/flex layout, text, button and keyed state;
3. one native window plus one GPU presentation backend;
4. shaping/fallback, clipping, images, scrolling and animation;
5. accessibility bridge and keyboard/IME conformance;
6. remaining desktop backends and promotion review.

Required tests include keyed reorder/state preservation, state retirement, nested
constraint cases, bidi and fallback goldens, clipping/compositing pixels, input
ordering, focus and pointer capture, resize/DPI changes, device loss, every resource
limit, accessibility tree/action fixtures, and leak-free repeated open/close. GPU
backends are compared against the CPU reference with declared per-pixel tolerances.

All seventeen asset/UI modules remain experimental until a general-purpose application
workload builds a multi-window, keyboard-accessible application on Windows, Linux and
macOS and records stable memory, frame-time and compatibility results.
