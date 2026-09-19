# Neper desktop and mobile widget library proposal

Status: research-backed design proposal. This document proposes the component
catalogue and its delivery order; it does not add declarations to
[`module-apis.md`](module-apis.md) or module identities to
[`modules.json`](modules.json).

[`widget-plan.json`](widget-plan.json) is the machine-readable implementation
inventory consumed by `scripts/render_progress.py` and continuation harnesses. This
document owns design intent; the inventory owns phase order, component status,
evidence and pickup order.

Research date: 2026-09-17.

## 1. Recommendation

Build one semantic widget system for desktop and mobile, with adaptive presentation
rather than separate desktop and mobile catalogues. Keep the existing immutable
`widget.Node`, persistent element, explicit state, bounded arena and GPU scene model.
Extend it in layers:

1. a small set of runtime primitives in `e.ui.widget`;
2. ordinary composite controls in a new `e.ui.control` module;
3. virtualized data views in `e.ui.collection`;
4. menus, popups and modal presentation in `e.ui.overlay`;
5. adaptive application navigation in `e.ui.navigation`.

Desktop and mobile are presentation profiles and capability sets, not forks. A
`Button`, `TextField` or `List` keeps the same value and action contract everywhere.
Theme metrics, window size, safe insets and active input devices determine its visual
density and interaction details. Controls whose behavior really differs—menu bar,
bottom sheet, system file picker—remain explicit.

The central implementation rule is:

> Add a runtime widget kind only when it owns reconciliation, focus, editing,
> virtualization, hit-testing or overlay behavior. Build everything else by composing
> those kinds.

This gives Neper a rich public catalogue without a giant `widget.Kind` union, hidden
allocation, per-control runtime classes or duplicated Material/Cupertino/desktop
implementations.

## 2. What established frameworks make standard

The catalogues use different names, but converge on the same families.

| Family | Flutter / Compose / SwiftUI | Qt / GTK / VCL | Conclusion for Neper |
| --- | --- | --- | --- |
| Content | text, image, icon, shape | label, image, rich text, canvas | Core primitives |
| Layout | row/column, stack, grid, wrap, padding, scrolling | layout managers, panels, splitters, scroll areas | Core primitives plus composites |
| Actions | buttons, icon/FAB buttons, links | push/tool/split buttons, actions | One command/action model, several presentations |
| Value input | text, checkbox, radio, switch, slider, picker | edit/memo, checkbox, radio, slider, spin, combo | Shared semantic controls |
| Feedback | progress, activity, badge, snackbar, tooltip | progress/status/info bars, tooltip | Shared controls; presentation adapts |
| Containers | card, scaffold, disclosure, tabs | frame/group box, tab/page, toolbar, status bar | Composite controls |
| Collections | lazy list/grid, list, table | list, icon, column/table, tree | Virtualized model/view contract is essential |
| Navigation | stack, tabs, drawer, rail, bottom navigation | menus, tabs, sidebars, toolbars | Adaptive navigation plus explicit desktop shell |
| Overlays | dialog, sheet, menu, popover | dialog, menu, popup, tooltip | One overlay/focus-placement subsystem |
| System integration | share, clipboard, drag/drop, file import | native dialogs, clipboard, drag/drop, tray, print | Host services, not ordinary widgets |

The important differences are emphasis, not fundamentals:

- Flutter and Jetpack Compose separate low-level composition from Material controls;
  Flutter also ships a Cupertino presentation family.
- SwiftUI shares view concepts across Apple platforms and adapts list, table,
  navigation and toolbar presentation to the current context.
- Qt exposes both touch-oriented Qt Quick Controls and desktop-oriented Qt Widgets.
  Its styles change appearance without changing control purpose.
- GTK 4 and Qt use model-backed virtualized list/column views for large data sets.
- VCL's long-lived desktop catalogue highlights menus, actions, rich edit, tree/list
  views, toolbars, status bars and common dialogs that mobile-first lists often omit.
- .NET MAUI and React Native distinguish pages/layouts/views or core/native
  components, reinforcing that platform services and page structure should not be
  confused with leaf controls.

## 3. Proposed public catalogue

The names below are concepts, not final declarations. Variants such as filled,
outlined, destructive or compact belong in option values and themes unless their
behavior differs.

### 3.1 Foundation and content

| Components | Required behavior |
| --- | --- |
| `Text`, `SelectableText`, `RichText` | Unicode shaping, wrapping, bidi, selection and links |
| `Icon`, `Image` | semantic label, tint, fit, scale and locale/theme asset variants |
| `Canvas`, `CustomPaint` | bounded custom display-list emission, pointer hit shape optional |
| `Surface`, `Panel`, `Card` | background, border, elevation, clipping and semantic grouping |
| `Divider`, `Badge`, `Avatar`, `Placeholder` | cheap composites; no dedicated runtime state |

`Avatar` and `Placeholder` are convenience composites, not new primitive kinds.
Network image loading is not a widget responsibility: applications load, decode and
cache bytes explicitly, then pass a texture or image resource.

### 3.2 Layout and responsive composition

| Components | Notes |
| --- | --- |
| `Box`, `Row`, `Column`, `Flex`, `Wrap` | linear and wrapping layout |
| `Grid`, `Stack`, `Positioned` | two-dimensional and overlay layout |
| `Align`, `Center`, `Padding`, `Spacer` | allocation-free convenience constructors |
| `Constrained`, `AspectRatio`, `Fitted` | deterministic constraint adapters |
| `ScrollView`, `Scrollbar` | one- or two-axis scrolling with explicit controller/state |
| `ZoomView` | bounded pan/zoom viewport for images, diagrams and custom content |
| `SplitView`, `ResizablePane` | pointer/keyboard-resizable desktop and tablet panes |
| `SafeArea`, `KeyboardAvoiding` | consume system and on-screen-keyboard insets |
| `Responsive` | choose a child from caller-declared size/capability breakpoints |

`Row`, `Column`, `Padding`, `Center` and similar names lower to existing layout
primitives. `Responsive` must use measured constraints, never a hard-coded
"mobile platform" test.

### 3.3 Actions and selection

| Components | Important variants or states |
| --- | --- |
| `Button` | normal, primary, tonal, outlined, text, destructive and floating variants |
| `IconButton`, `ToggleButton` | mandatory accessible label; selected state |
| `SplitButton`, `MenuButton` | primary action plus menu or menu-only action |
| `SpeedDial` | composite floating action that expands a short action list |
| `Link` | URI or application action; keyboard and visited semantics |
| `Checkbox` | unchecked, checked, mixed |
| `Radio`, `RadioGroup` | group-owned single selection and arrow-key traversal |
| `Switch` | immediate binary setting, distinct semantics from checkbox |
| `SegmentedControl` | single or multiple compact selection |
| `Chip` | assist, filter, input and suggestion behavior as variants |
| `Slider`, `RangeSlider` | continuous/discrete steps, keyboard increments |
| `SpinBox`, `Stepper` | numeric editing or increment/decrement presentation |
| `Dial` | circular bounded value input for instrument and media interfaces |
| `Rating` | discrete value input; composite over selection primitives |
| `ShortcutRecorder` | capture and validate a keyboard shortcut or chord |

All value controls are controlled by default: the caller supplies the current value
and a typed change action. Internal state is limited to transient interaction such as
pressed, hovered, composition, caret and drag position. This keeps application state
serializable and makes rebuilds deterministic.

### 3.4 Text entry and forms

| Components | Required behavior |
| --- | --- |
| `TextField`, `PasswordField`, `SearchField` | single-line edit, IME, selection, undo, validation state |
| `TextArea` | multiline edit, scrolling, line and selection navigation |
| `FormattedField` | caller-supplied parse/format/validate adapter |
| `Autocomplete` | text entry plus caller-filtered suggestions and active-item semantics |
| `TokenField` | editable sequence of removable values with suggestions |
| `ComboBox` | editable text plus filtered popup choices |
| `Select`, `Picker` | non-editable choice; popup, wheel or sheet presentation |
| `Form`, `FormField`, `FieldLabel`, `FieldMessage` | label/help/error relationships and responsive form layout |
| `ValidationSummary` | links form-level errors back to their fields |

Do not create database-aware versions of every input as VCL does. A small binding
adapter can connect controlled values and change actions to any model. Validation is
data (`valid`, `warning`, `invalid`, message and accessibility relationship), not an
exception or a paint-only red border.

Text editing is a runtime primitive, not a composite of `Text` and pointer handlers.
It must own caret/selection geometry, composition ranges, clipboard commands,
platform IME coordination and bounded undo history.

### 3.5 Feedback, status and disclosure

| Components | Notes |
| --- | --- |
| `ProgressBar`, `ProgressRing` | determinate and indeterminate; reduced-motion behavior |
| `Gauge`, `Level` | read-only bounded value display |
| `Tooltip` | hover, focus and long-press activation |
| `Toast`, `Snackbar` | queued transient notice; optional action |
| `Banner`, `InfoBar` | persistent inline status with severity and actions |
| `Skeleton` | theme animation disabled under reduced motion |
| `EmptyState` | composite content/action pattern |
| `Disclosure`, `Expander`, `Accordion` | keyboard-operable expanded state |

`Toast` and `Snackbar` share queueing behavior but may use different theme and
placement policies. They should not be two independent runtime systems.

### 3.6 Collections and data presentation

| Components | Required behavior |
| --- | --- |
| `List`, `VirtualList` | keyed lazy rows, selection, sections, separators and variable extent |
| `ListBox`, `MultiSelectList` | compact selectable list with single or multiple selection |
| `GridView`, `VirtualGrid` | keyed lazy cells, adaptive column count |
| `Carousel`, `PageView` | paged collection with pointer, touch and keyboard navigation |
| `PageIndicator`, `Pagination` | compact page position or explicit page navigation |
| `Table`, `DataGrid` | virtual rows, columns, sort, resize, reorder, pin, select and edit |
| `Tree`, `Outline` | lazy hierarchical expansion, multi-selection and keyboard traversal |
| `TreeTable` | hierarchical rows with sortable/resizable columns |
| `ReorderableList` | drag/keyboard reorder with explicit move action |
| `PullToRefresh`, `SwipeActions` | touch collection behaviors with keyboard/action alternatives |

These controls consume a bounded callback-based data source rather than a slice of
prebuilt nodes. The minimum source contract is item count, stable key and item build.
Tables add column metadata and cell building; trees add child count and expansion.
Only visible items plus configurable overscan may become elements.

Selection is a caller-owned set of stable keys, not row indices. Sorting and
filtering emit requests; the widget does not copy or mutate the application's model.
`List` may accept static children for small lists, while `VirtualList` always uses a
source.

### 3.7 Navigation and application structure

| Components | Typical use |
| --- | --- |
| `AppBar`, `Toolbar`, `StatusBar` | window/page actions and status |
| `MenuBar`, `Menu`, `ContextMenu` | desktop and pointer/keyboard commands |
| `Tabs`, `TabView` | peer destinations or document views |
| `DocumentTabs` | closeable/reorderable documents with dirty and pinned states |
| `NavigationStack` | push/pop application destinations |
| `NavigationSplit` | master-detail and two/three-column layouts |
| `NavigationDrawer`, `NavigationRail`, `BottomNavigation` | equivalent top-level destinations at different widths |
| `Breadcrumbs`, `Sidebar` | hierarchical desktop/tablet navigation |
| `Wizard` | explicit ordered steps with validation and back/next actions |
| `WindowSwitcher` | application-owned selection among open windows/documents |
| `CommandPalette` | searchable application commands; phase 3 composite |

Navigation state is caller-owned data: stable destination IDs and an explicit path.
The control renders transitions and produces push, pop and selection actions. It does
not own application models or use type-erased reflective routes.

An adaptive navigation shell may choose bottom navigation on compact touch screens,
a rail at medium width and a sidebar at large width. The three explicit controls
also remain available; adaptation is never forced.

### 3.8 Overlays and transient presentation

| Components | Required behavior |
| --- | --- |
| `Popup`, `Popover`, `Flyout` | anchored placement, flip/shift, dismissal and focus return |
| `Dialog`, `AlertDialog` | modal focus scope, default/cancel/destructive actions |
| `Sheet`, `BottomSheet`, `ActionSheet` | adaptive modal/nonmodal presentation and drag dismissal |
| `Menu`, `ContextMenu` | nested keyboard navigation, type-ahead and checked items |
| `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
| `ColorPicker` | color model plus optional native-host presentation |
| `FontPicker` | family/style/size selection over a caller- or host-supplied font catalogue |

All transient UI must go through one overlay manager so z-order, clipping, focus
traps, pointer dismissal, accessibility modality and anchor placement are consistent.
A dialog is not merely a `Stack` painted above the root.

### 3.9 Interaction modifiers and controllers

These are reusable behaviors rather than visible components:

- focus scope/order, focus request and default focus;
- shortcut and mnemonic handling;
- tap/click, double-click, long-press, pan, pinch and hover recognition;
- drag source, drop target and transferable payload metadata;
- pointer capture, cursor and context-menu attachment;
- scroll, text-edit, selection, tab and navigation controllers;
- semantics, test ID, live-region and tooltip attachments;
- enabled, read-only, visible and input-transparent state.

Gesture recognizers consume the ordered pointer stream already planned in
`e.ui.input`; they must arbitrate through an explicit bounded gesture arena so a
scroll drag and child tap do not both win.

### 3.10 Host services, not widgets

Keep the following behind reviewed platform services and capability queries:

- open/save/folder, color and font system dialogs;
- clipboard, drag exchange with other applications and share sheet;
- notifications, badges, haptics and mobile system/status/navigation bars;
- system tray, jump lists, global menus and taskbar integration;
- printing and print/page setup;
- camera, photo library and permission prompts;
- application lifecycle, deep links and multi-window scene lifecycle;
- virtual keyboard visibility and safe-area/system-bar insets.

The widget layer may offer buttons or controllers that invoke these services, but it
must not fake platform security UI or embed direct platform `extern`s.

The standard library still owns typed, portable controllers for the most common
shell integrations. They are counted delivery work, but become available only when
the host reports the corresponding capability:

| Components | Required behavior |
| --- | --- |
| `SystemTray`, `TrayMenu`, `TrayBadge` | create/update/remove a tray or status item, attach a command menu, surface activation, and expose unsupported capability cleanly |
| `JumpList`, `TaskbarProgress`, `TaskbarOverlay` | publish Windows Jump List tasks/recent items and taskbar progress/overlay state without leaking COM declarations into application code |
| `SystemNotification`, `NotificationActions`, `NotificationPermission` | query/request permission, publish/update/remove an OS notification, route action and activation payloads, and report unavailable or denied state |
| `ContentType`, `DataOffer`, `DataRepresentation`, `DataProvider` | one typed, lazy/async data-transfer model mapped to MIME, UTI and native platform formats |
| `SystemDragSource`, `SystemDropTarget`, `DragOperation`, `PromisedFile` | cross-process and desktop drag/drop for files, directories, text, URLs, images and custom types with copy/move/link results and scoped access |
| `SystemClipboard`, `ClipboardMonitor`, `ShareSheet`, `ShareTarget` | typed multi-representation clipboard and operating-system share send/receive flows without unsolicited private-data reads |
| `OpenFileDialog`, `SaveFileDialog`, `FolderDialog`, `DocumentGrant`, `RecentDocuments` | native file/folder selection, filters, multi-select, sandbox grants/bookmarks and recent-document publication |
| `ActivationEvent`, `FileAssociation`, `ProtocolAssociation`, `StartupRegistration`, `SingleInstanceActivation` | declarative package registration plus runtime routing for launch, files, URLs, startup and redirected activation |
| `OpenUri`, `RevealInFileManager`, `MoveToTrash` | delegate URI opening, file reveal and recoverable deletion to the host shell |
| `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware global input, login/background work, sleep inhibition, shutdown/suspend events and state restoration |
| `PrintDialog`, `PageSetupDialog`, `PrintJob` | native print/page setup UI, cancellable job state and host error reporting |
| `PermissionStatus`, `CameraAccess`, `MicrophoneAccess`, `PhotoLibraryPicker`, `LocationAccess`, `BiometricAuthentication`, `CredentialStore`, `ScreenCapture` | capability/permission-gated hardware, identity, secret storage and capture services; never imitate protected system prompts |

`Toast`, `Snackbar`, `Banner` and `NotificationList` are application-owned UI;
they do not imply operating-system notification support.
Likewise, phase-2 `DragSource`, `DropTarget` and `ClipboardCommands` are widget
attachments and command routing. Their cross-application behavior is supplied by
the phase-4 system data-exchange services rather than a second widget implementation.

Web views, maps, PDF viewers, video players, charts, code editors, terminal emulators
and native-view embedding should be extension packages. They are valuable, but they
have independent engines, security boundaries or data models and should not delay the
general widget library.

### 3.11 Desktop productivity composites

| Components | Required behavior |
| --- | --- |
| `PropertyGrid`, `KeyValueEditor` | categorized editable properties, validation and reset actions |
| `DockLayout`, `DockPanel` | tab, split, float and restore caller-owned workspace layout |
| `MultiDocumentWorkspace` | document tabs, window switching and close/save coordination |
| `NotificationList` | persistent application-owned history behind transient toast/banner UI |

These are phase 3 composites over collections, overlays, split views and commands.
They do not justify new runtime primitives until an editor-class reference workload
shows a missing low-level capability.

### 3.12 Aliases and presentation variants

Familiar toolkit names do not always need distinct Neper controls:

- `Label` is `Text`; `ActivityIndicator` is an indeterminate `ProgressRing`;
- `FloatingActionButton` is a `Button` variant and its expanded form is `SpeedDial`;
- `MessageBox` and `InputDialog` are convenience builders over `AlertDialog` and
  `Dialog`;
- `MaskEdit` is a `FormattedField`; a toggle group is `SegmentedControl` or grouped
  `ToggleButton` values;
- a refresh indicator is the presentation used by `PullToRefresh`;
- `Row`, `Column`, `Padding`, `Center` and similar names remain allocation-free layout
  constructors.

This preserves names developers expect without multiplying runtime kinds or parallel
implementations.

## 4. Runtime primitive set

The current `Kind` list mixes low-level layout with a high-level `Button`. Replace
that direction with a small behavioral basis. The exact names can change during API
design, but the capabilities should be:

| Primitive | Why it must exist in the runtime |
| --- | --- |
| layout/paint nodes | measurement, child placement, clipping and display-list output |
| text/image/custom paint | leaf measurement and paint resources |
| action/gesture region | hit testing, capture and gesture arbitration |
| focus/shortcut scope | traversal, keyboard dispatch and default/cancel actions |
| editable text | IME, selection, caret, clipboard and undo |
| scroll viewport | offset, momentum, overscroll policy and scrollbar coordination |
| lazy viewport | visible-range calculation and element recycling by stable key |
| semantics node | accessible role, state, relationships and actions |
| overlay portal/anchor | root-level paint, placement, modality and focus restoration |

`Button`, `Checkbox`, `Card`, `Tabs` and most of the catalogue then become ordinary
functions that return node subtrees. Composite internals use reserved child keys
derived from the caller's key so reconciliation remains deterministic.

## 5. Common value and action contracts

The current untyped `Action` receives only `input.Event`, which is sufficient for a
press but awkward for text, selection, numeric values and navigation. Add typed,
non-capturing actions at the control layer. A representative, non-normative shape is:

```neper
type Change[T: type] = struct {
    ctx: *void,
    invoke: fn(*void, T) -> err,
}

type Submit = struct {
    ctx: *void,
    invoke: fn(*void) -> err,
}

type ItemSource = struct {
    ctx: *void,
    count: fn(*const void) -> usize,
    key: fn(*const void, usize) -> widget.Key,
    build: fn(*void, *mem.Arena, usize) -> (widget.Node, err),
}
```

Actions follow the existing lifetime rule: `ctx` outlives its element and never
points into the frame arena. Strings passed to change actions are borrowed for the
call; an application that retains one copies it to owned storage. A callback failure
aborts the current dispatch and returns through `app.step` without partially
committing a new tree.

Controls should expose concepts, not paint anatomy. A button accepts content, action,
enabled state and semantic variant; it does not publish thumb offsets, ripple objects
or platform widget handles. Slot-like child content is preferred to dozens of label,
icon and subtitle properties.

## 6. Theme and adaptive behavior

Extend `e.ui.style` with explicit theme values rather than CSS selectors or a global
mutable theme:

- color roles, typography roles, spacing, radii, borders and elevation;
- motion durations/curves and reduced-motion alternatives;
- minimum hit target, control height, pointer density and focus-ring metrics;
- control variants resolved for normal, hovered, pressed, focused, selected,
  disabled, read-only and invalid states;
- light, dark, high-contrast and caller-defined palettes;
- platform presentation profile and text direction.

The theme is passed through build context and may be overridden for a subtree. A
component resolves its immutable style during build. There is no selector matching,
cascade, string property lookup or runtime reflection.

Use three independent inputs for adaptation:

1. **constraints:** compact, medium or expanded space;
2. **capabilities:** hover, fine pointer, keyboard, touch, pen, safe insets and
   resizable/multi-window host;
3. **theme profile:** Neper, desktop-dense, touch, Material-like or
   Cupertino-like presentation supplied by the application or an extension package.

Do not assume a device has only one input modality. A tablet may have touch, pointer
and keyboard at the same time, and a desktop window may be narrow.

## 7. Accessibility contract

Accessibility is part of each control's definition, not a later wrapper. Expand the
planned semantics API before adding the catalogue:

- roles for switch, tab/tab list, menu/menu item, dialog/alert, heading, status,
  tooltip, tree/tree item, grid, row header and column header;
- states for mixed, busy, invalid, required, read-only, modal and current;
- relationships for label, description, error, controls and active descendant;
- actions for dismiss, expand/collapse, select, show menu, set selection and custom
  named actions;
- text ranges, caret, selection and editable-value operations;
- live-region politeness and collection row/column metadata.

Every interactive control must support keyboard access, visible focus, logical
reading order, touch target metrics, high contrast, text scaling and reduced motion.
Icon-only controls require a semantic label. Disabled controls remain discoverable
when platform conventions require it; hidden controls do not appear in the tree.

## 8. Required changes to the current framework proposal

Before the catalogue can be implemented safely, the lower-level contracts need these
additions:

- `e.ui.input`: pointer enter/leave, hover, wheel/trackpad delta and phase, pressure
  and tilt where available, gesture cancellation, drag/drop, mobile back, safe/system
  inset changes and explicit lifecycle events;
- `e.ui.window`: screen/work-area metrics, safe and keyboard insets, orientation,
  multiple windows/scenes and capability queries;
- `e.ui.widget`: typed control actions, focus scopes/traversal, gesture arbitration,
  editable text, lazy viewport and overlay portal primitives;
- `e.ui.style`: borders, corner radii, foreground/text roles, control-state theme
  resolution, density and accessibility preferences;
- `e.ui.accessibility`: the roles, states, relationships and editable text operations
  listed above;
- `e.ui.testing`: semantic queries, focus traversal, fake IME, gesture sequences,
  overlay lookup, viewport visibility and host capability/inset fixtures.

Mobile support also needs a separate host lifecycle proposal, as anticipated by
[`ui-framework.md`](ui-framework.md). The widget catalogue itself should not wait for
that host work: components can be tested against synthetic compact/touch capabilities
before Android and iOS presentation backends exist.

## 9. Module boundaries

Do not create one module per widget. The following five public areas are enough. The
four new names remain candidate modules until phase 0 freezes their first API fences
and adds them to `modules.json` and `module-apis.md` in the same change:

| Module | Responsibility |
| --- | --- |
| `e.ui.widget` | node/runtime primitives, reconciliation, state, focus and gestures |
| `e.ui.control` | themed content, action, input, form, feedback and container composites |
| `e.ui.collection` | lazy sources, list/grid/table/tree and selection contracts |
| `e.ui.overlay` | popup placement, menus, tooltip, toast, dialog and sheet presentation |
| `e.ui.navigation` | paths, tabs, app bars, drawer/rail/bottom navigation and split navigation |

`e.ui.control` depends on `widget`, `style` and `accessibility`; the other three
depend on `control` only where they reuse visible controls. Platform services remain
in reviewed host-facing modules. Specialized components live in owner-qualified
packages until repeated use proves they belong in the standard library.

## 10. Delivery plan

The machine order is `widget-plan.json`: in the lowest phase whose phase blockers
are complete, select the first incomplete item whose own blockers are complete, then
the first undelivered component in that item. A delivery change adds the component to
`delivered`, records concrete test
or source evidence, regenerates `progress.html`, and freezes any newly exposed public
declaration in the module plan. `python scripts/check_widget_plan.py --next` reports
the current blocker or exact next component. Optional phase 5 ecosystem packages are not counted
in standard widget-library readiness.

### Phase 0 — contracts and reference theme

- finish focus, semantics, typed actions, gestures, editable text and overlay design;
- add theme tokens and normal/hover/press/focus/disabled/invalid resolution;
- build a CPU-rendered reference theme and a widget gallery test application.

Exit: every primitive has deterministic layout, paint, semantics and input fixtures.
The candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and
`e.ui.navigation` identities and their phase-1 public fences are now frozen in the
module plan; later phases extend those fences only with an explicit compatibility
decision.

### Phase 1 — useful desktop and mobile core

- content/layout: text, icon, image, surface, flex/grid/stack/wrap, scroll, safe area;
- controls: button families, link, checkbox, radio, switch, slider, progress;
- entry/forms: text field, password, search, text area, select, list box and form field;
- containers: card, group, disclosure, tabs and split view;
- overlay basics: tooltip, menu, alert/dialog;
- navigation basics: app bar, toolbar, navigation stack and adaptive destination bar.

Exit: one codebase implements a settings or CRUD application in a desktop window and
a synthetic compact touch host, with keyboard, IME and accessibility coverage.

### Phase 2 — scalable application UI

- virtual list/grid, sections, multi-selection, reorder, pull-to-refresh and swipe actions;
- popup/popover, context/menu bar, toast/snackbar/banner and sheets;
- drawer, rail, bottom navigation, sidebar, breadcrumbs and navigation split;
- page indicator/pagination, zoom view, autocomplete and token field;
- date/range/time/duration/calendar pickers, combo box, spin box and segmented controls;
- drag/drop, shortcut recorder, mnemonics and clipboard command routing.

Exit: mail/file-manager workloads remain bounded and responsive with 100,000 logical
items while creating elements only for the visible range plus overscan.

### Phase 3 — productivity controls

- data grid/tree table with sortable/resizable/reorderable columns and editable cells;
- tree/outline, property grid, rich selectable text, color/font pickers and command palette;
- document tabs, wizard, window switcher and docking/resizable workspace patterns if
  an editor-class reference app proves need;
- host file dialogs and printing as separate capability-gated work.

Exit: an editor/database-admin workload passes desktop keyboard, screen-reader,
multi-window and large-data tests.

### Phase 4 — host OS integration

- system tray/status items with command menus and badge state;
- Windows Jump Lists, taskbar progress and taskbar overlay icons;
- operating-system notifications, actions, activation routing and permission state;
- typed clipboard, sharing and cross-application/desktop drag and drop;
- native file/folder dialogs, sandbox document grants and recent documents;
- file/protocol/startup associations, deep links and single-instance activation;
- URI opening, file-manager reveal and recoverable trash/recycle operations;
- global shortcuts, login/background permission, lifecycle restoration and power inhibition;
- native printing, page setup and cancellable print jobs;
- capability-gated camera, microphone, photo library, location, biometric,
  credential-store and screen-capture services.

Its individual work items are blocked on the reviewed `native-shell-api`,
`native-notification-api`, `native-data-exchange-api`, `native-file-access-api`,
`native-activation-api`, `native-lifecycle-api`, `native-print-api` or
`native-permission-api` host primitive they require. Unrelated items can proceed when
their own primitive is ready. Unsupported platforms must return an
explicit capability result; they must not silently emulate protected OS integration
with in-app UI.

Exit: desktop and mobile reference apps exercise data exchange, file grants,
activation, lifecycle, shell, notification and permission flows on each supported
host, with deterministic unsupported/denied tests elsewhere.

### Phase 5 — optional ecosystem packages

- platform presentation packs;
- charts, media, web, map, PDF, code-editor and native-view adapters;
- domain component packs built on the stable primitive/control contracts.

## 11. Conformance and quality gates

Each public component needs a compact contract covering value ownership, actions,
focus, keyboard map, pointer/touch behavior, semantics, layout, theme states and
resource bounds. The shared conformance matrix must include:

- Windows, Linux and macOS desktop hosts; synthetic Android/iOS capability profiles
  until native hosts land;
- mouse, trackpad, keyboard-only, touch and pen input, including mixed modality;
- compact, medium and expanded widths; resize during interaction; DPI/scale changes;
- left-to-right and right-to-left layout, long translations and large text;
- IME composition, emoji/grapheme selection, password behavior and clipboard;
- light, dark, high-contrast and reduced-motion themes;
- screen-reader names, roles, states, relationships, actions and focus restoration;
- empty, one-item, huge, disabled, read-only, invalid and callback-error states;
- overlay collision/flip, nested menus, modal focus trapping and escape/back dismissal;
- bounded memory, visible-range virtualization and leak-free repeated mount/unmount.

Golden pixels alone are insufficient. Tests should assert semantic trees, focus
order, emitted typed actions, visible item ranges and deterministic state retention.

## 12. Explicit non-goals

- cloning every Flutter, Material, Cupertino, Qt, GTK or VCL class;
- wrapping native controls on each platform as the primary renderer;
- CSS, selector engines, inheritance-heavy widget classes or runtime reflection;
- implicit two-way database binding or a global observation graph;
- hidden networking, filesystem access, threads or unbounded caches inside controls;
- promoting specialist engines to the standard library before reference applications
  and stable extension points exist.

## 13. Research sources

Primary framework documentation used for this comparison:

- [Flutter widget catalogue](https://docs.flutter.dev/ui/widgets), including its base,
  Material and Cupertino split.
- [Flutter Material components](https://docs.flutter.dev/ui/widgets/material) and
  [Cupertino widgets](https://docs.flutter.dev/ui/widgets/cupertino).
- [SwiftUI overview](https://developer.apple.com/documentation/swiftui/),
  [controls and indicators](https://developer.apple.com/documentation/swiftui/controls-and-indicators),
  [lists](https://developer.apple.com/documentation/swiftui/list),
  [tables](https://developer.apple.com/documentation/swiftui/tables) and
  [navigation stacks](https://developer.apple.com/documentation/swiftui/navigationstack).
- [UIKit views and controls](https://developer.apple.com/documentation/uikit/views-and-controls).
- [VCL standard controls](https://docwiki.embarcadero.com/RADStudio/Athens/en/Standard_Controls),
  [Win32 controls](https://docwiki.embarcadero.com/RADStudio/Athens/en/Win32_Controls)
  and [component categories](https://docwiki.embarcadero.com/RADStudio/en/VCL_Components_Categories_Index).
- [GTK 4 widget gallery](https://docs.gtk.org/gtk4/visual_index.html) and
  [GTK 4 API index](https://docs.gtk.org/gtk4/), including its model-backed
  `ListView` and `ColumnView`.
- [Qt Quick Controls](https://doc.qt.io/qt-6/qtquickcontrols-index.html),
  [Qt Widgets classes](https://doc.qt.io/qt-6/widget-classes.html) and
  [Qt UI technology comparison](https://doc.qt.io/qt-6/topics-ui.html).
- [.NET MAUI controls](https://learn.microsoft.com/dotnet/maui/user-interface/controls/),
  organized as pages, layouts and views.
- [Jetpack Compose Material components](https://developer.android.com/develop/ui/compose/components)
  and [layout fundamentals](https://developer.android.com/develop/ui/compose/layouts/basics).
- [React Native core components](https://reactnative.dev/docs/components-and-apis),
  particularly its distinction between basic components, virtualized lists and
  platform-specific APIs.
