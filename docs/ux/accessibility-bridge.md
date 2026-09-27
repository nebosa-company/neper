# The screen-reader bridge

`e.ui.accessibility` builds a semantic tree of the widget runtime (D904, D1598). The
bridge publishes that tree to the host's assistive technology and carries the
person's actions back into the widgets. On Windows the host is UI Automation, which
Narrator, NVDA and JAWS read (D1602). On Linux it is AT-SPI over D-Bus, which Orca
and Accerciser read (D1603). macOS (NSAccessibility) is not written yet.

An `e.ui.app` program does nothing to use the bridge: the app loop publishes and
serves requests on its own. A program that runs its own loop calls the same three
functions `e.ui.app` calls (see [Wiring](#wiring)).

## What flows where

```
widget runtime ──build──▶ accessibility.Tree ──flatten_into──▶ []os.AccessibleNode
       ▲                                                          │ accessibility_publish
       │ perform (focus, press, set value, select, ...)           ▼
accessibility.serve ◀── os.accessibility_take ◀── host store (copied records + text)
                                                                  ▲       │
                                                  method calls ───┘       └──▶ events
                                              (UIA / AT-SPI client)          (focus, structure)
```

1. **Publish.** Each frame, `accessibility.present` asks
   `os.accessibility_listening`. If an assistive technology has asked for the
   window, the tree is built in the frame arena, flattened, and handed to
   `os.accessibility_publish`. If none has asked, nothing is built.
2. **Flatten.** `flatten_into` writes one `os.AccessibleNode` per node in tree
   order: each parent comes before its children, and siblings keep their order.
   Each record names its parent by slot and generation. Hosts rebuild children and
   siblings from that order.
3. **Keep.** The host side copies every record and its label, value and hint into a
   store it owns: reserved memory per window (8 MB on Windows, 4 MB on Linux),
   never freed. The copy is
   needed because the frame arena is reset every frame. The store is indexed by
   widget slot, so a lookup by id is one array read.
4. **Answer.** Client calls are answered from the store, on the window's thread,
   between frames: UIA through `WM_GETOBJECT`, AT-SPI through the socket polled
   beside the X display.
5. **Act.** An action from the client (invoke, toggle, select, expand, set value,
   set caret, focus) is queued as an `os.AccessibleRequest`. The host then wakes
   the program's wait with a Paint event. On the next step `accessibility.serve`
   takes each request and runs it through `accessibility.perform`, the same path
   the audit and the tests use. A pointer press reaches the widget exactly as a
   click would.
6. **Tell.** After a publish the host signals what changed. When the focused node
   changes it raises the focus event: UIA_AutomationFocusChangedEventId, or
   `StateChanged("focused", 1)`. On the first publish it raises the structure
   change: ChildrenInvalidated, or `ChildrenChanged("add")`.

## Identity

A published element is its widget **slot and generation**. Across frames, the same
element keeps the same UIA runtime id (`[UiaAppendRuntimeId, slot, generation]`)
and the same AT-SPI path (`/org/a11y/atspi/accessible/<window>_<slot>_<generation>`).
When a node disappears, or its slot is reused under a new generation, calls on the
old element answer that it is gone: `UIA_E_ELEMENTNOTAVAILABLE`, or
`org.freedesktop.DBus.Error.UnknownObject`. That is what clients expect of a defunct
element.

## Privacy

A field that masks its value (`secret`, D823) reaches the tree as its mask, one
asterisk per byte, never as the value (D1604). The node carries the new `secret`
state bit (8192). UIA reports `IsPassword`; AT-SPI gives the role `PASSWORD_TEXT`.
Before D1604 the tree copied the raw buffer. No assistive client could read it then,
because nothing published the tree, but the bridge would have exposed it.

## Windows: UI Automation (D1602)

A server-side provider written in `lib/e/os.windows.e`, with no helper DLL and no
COM registration.

- `WM_GETOBJECT` with `UiaRootObjectId` returns the window's root element through
  `UiaReturnRawElementProvider`. The root delegates its name and frame to the
  window's own provider (`UiaHostProviderFromHwnd`). The first such message creates
  the window's store and queues a frame so the tree exists before the client looks.
- Each element is one object per widget slot. It holds one interface pointer for
  each interface it answers, and each pointer is the address of its own field. A
  method finds its element by looking up which vtable its pointer names. The
  objects are never freed, so AddRef and Release return 1.
- Interfaces: `IRawElementProviderSimple`, `IRawElementProviderFragment`,
  `IRawElementProviderFragmentRoot` (root only), and the patterns `IInvokeProvider`,
  `IValueProvider`, `IToggleProvider`, `IExpandCollapseProvider` and
  `ISelectionItemProvider`.
- Properties: ControlType, Name, HelpText (the hint), HasKeyboardFocus,
  IsKeyboardFocusable, IsEnabled, IsOffscreen, IsPassword, IsRequiredForForm,
  LabeledBy, LiveSetting and HeadingLevel.
- An unnamed group, or anything inside a button, tab, box, range or separator
  (ARIA's presentational children), sets IsControlElement and IsContentElement to
  false. The control view, which is what Narrator walks, then reads like a native
  app: a TabItem "Buttons", not a TabItem holding a Text "Buttons".
- Bounds are screen pixels: the client origin (`ClientToScreen`) plus the logical
  box at `GetDpiForWindow / 96`.

| `e.ui` role | UIA control type | patterns |
|---|---|---|
| Button, Switch | Button | Invoke (Switch: Toggle) |
| Checkbox, MenuItemCheckbox | CheckBox, MenuItem | Toggle |
| Radio, MenuItemRadio, Tab, Option | RadioButton, MenuItem, TabItem, ListItem | SelectionItem |
| TextField, Combobox, SpinButton | Edit, ComboBox, Spinner | Value |
| Text, Heading, Alert | Text (Heading: HeadingLevel) | |
| List, Listbox / ListItem | List / ListItem | SelectionItem when selectable |
| Table, Grid, TreeGrid / Row, Cell | Table, DataGrid / DataItem | |
| Tree / TreeItem | Tree / TreeItem | ExpandCollapse when expandable |
| TabList, Menu, MenuBar, Status, Tooltip, Slider, Progress, Scrollbar, Separator, Link, Image | the same-named type | |
| Group, Region, Main | Group | |
| Window, Dialog, AlertDialog, other | Pane | |

Any node whose actions include Expand or Collapse also gets ExpandCollapse, and any
node with Select gets SelectionItem.

## Linux: AT-SPI over D-Bus (D1603)

A D-Bus client written in `lib/e/os.linux.e`. It speaks the wire protocol over a raw
`AF_UNIX` socket, the same way the X11 client in that file does. It uses no libdbus
and no libatspi.

- **Connect.** When the first window opens, the bridge reads
  `DBUS_SESSION_BUS_ADDRESS`, authenticates with `AUTH EXTERNAL` as the process's
  user, and calls `Hello`. It then asks `org.a11y.Bus.GetAddress` for the
  accessibility bus and connects to that the same way. Finally
  `org.a11y.atspi.Socket.Embed` on the registry places the application under the
  desktop. If any step fails, the bridge stays off and the program never sees an
  error. Each wait is bounded (2 s per read). Setting `NO_AT_BRIDGE=1` keeps the
  bridge off, as it does for GTK and Qt.
- **Serve.** `x_drain` polls the bus socket beside the display. A client that walks
  the tree sends its next call as soon as the last one is answered, so the bridge
  keeps answering while calls keep coming: 1 ms apart, up to 64 reads per step. It
  does not stop at one call per frame. Without this, a 400-call walk of the
  gallery took minutes once a caret was blinking; with it, it takes seconds.
- **Objects.** `.../accessible/root` is the application (role APPLICATION, toolkit
  `neper`). `.../accessible/<window>` is a window's FRAME, named by its title.
  `.../accessible/<window>_<slot>_<generation>` is a node.
- **Interfaces.** `Accessible` (children, index in parent, role, state, attributes
  such as a heading's `level`, relations LABELLED_BY / DESCRIBED_BY /
  CONTROLLER_FOR / ERROR_MESSAGE, interfaces, application), `Component` (extents,
  position, size, contains, accessible-at-point, layer, grab focus), `Action`
  (click, increment, decrement, scroll, dismiss, expand, collapse, select,
  showmenu and copy, by the node's action bits), `Text` and `EditableText` for
  entries (character-counted offsets, caret, selection, set text contents),
  `Application`, and `org.freedesktop.DBus.Properties` Get, GetAll and Set.
- **State bits** follow AtspiStateType: ENABLED, SENSITIVE, VISIBLE, SHOWING,
  FOCUSABLE, FOCUSED, SELECTABLE, SELECTED, CHECKABLE, CHECKED, INDETERMINATE,
  EXPANDABLE, EXPANDED, BUSY, INVALID_ENTRY, REQUIRED, MODAL, READ_ONLY, EDITABLE,
  SINGLE_LINE, and ACTIVE on a focused frame. All role and state numbers were taken
  from a C program compiled against `atspi-constants.h`, not typed by hand.

| `e.ui` role | AT-SPI role |
|---|---|
| Button / Switch | PUSH_BUTTON / TOGGLE_BUTTON |
| Checkbox, Radio | CHECK_BOX, RADIO_BUTTON |
| Text / Heading | LABEL / HEADING |
| TextField | ENTRY, or PASSWORD_TEXT when secret |
| List, ListItem, Option, Listbox | LIST, LIST_ITEM, LIST_ITEM, LIST_BOX |
| Table, Grid / Row / Cell / headers | TABLE / TABLE_ROW / TABLE_CELL / TABLE_ROW_HEADER, TABLE_COLUMN_HEADER |
| Tree / TreeItem / TreeGrid | TREE / TREE_ITEM / TREE_TABLE |
| Tab / TabList | PAGE_TAB / PAGE_TAB_LIST |
| Menu, MenuBar, MenuItem, MenuItemCheckbox, MenuItemRadio | MENU, MENU_BAR, MENU_ITEM, CHECK_MENU_ITEM, RADIO_MENU_ITEM |
| Dialog, AlertDialog / Alert / Status / Tooltip | DIALOG / ALERT / STATUS_BAR / TOOL_TIP |
| Slider, Progress, Scrollbar, SpinButton, Combobox, Separator, Link, Image | the same-named role |
| Region, Main | LANDMARK |
| Group, Window, other | PANEL |

## The API

`e.os`, on both hosts:

- `type AccessibleNode`: the flat record (D802), unchanged.
- `type AccessibleRequest = struct { id: u32, generation: u32, action: u8, value: str }`:
  `action` is `e.ui.accessibility.Action` in declaration order. `value` is the text
  a SetValue carries, or `"start:end"` in bytes for a SetSelection. The value is
  valid until the next take.
- `fn accessibility_listening(w: Window) -> bool`: whether an assistive technology
  has asked for this window.
- `fn accessibility_publish(w: Window, nodes: []const AccessibleNode) -> err`: keeps
  the records if something is listening, and does nothing otherwise.
- `fn accessibility_take(w: Window) -> (AccessibleRequest, bool)`: the oldest
  pending request.

`e.ui.accessibility`:

- `fn listening(window.Id) -> bool`
- `fn present(a: *mem.Arena, runtime: *const widget.Runtime, window.Id) -> err`:
  build and publish when something is listening.
- `fn serve(runtime: *widget.Runtime, window.Id) -> bool`: perform every pending
  request; true when anything was performed.
- `fn flatten_into(t, storage) -> err`: now in tree order (D1604).

## Wiring

`e.ui.app` does this for you. In `step`, after input:

```
if accessibility.serve(&s.runtime, s.win.id) { s.frame_due = true }
if !s.assisted && accessibility.listening(s.win.id) { s.frame_due = true }
```

In `present_frame`, after reconcile:

```
if accessibility.listening(s.win.id) {
    s.assisted = true
    let presented = accessibility.present(&frame, &s.runtime, s.win.id)
}
```

A tree that fails to build (for example, the frame arena is full) is not published,
and the frame goes on.

## Verifying it

Fixtures, run by the suites:

- `tests/selfhost/fixtures/link/os_uia` (Windows, `run.ps1`) answers a real
  `WM_GETOBJECT`, publishes records, then calls the provider's methods as UI
  Automation does. It checks navigation in order, names read back as BSTRs, control
  types, presentational children, IsPassword, patterns, toggle state, value, screen
  bounds, requests with a UTF-8 value, the focus, and gone elements after a
  republish and after the window closes.
- `tests/selfhost/fixtures/link/os_atspi` (Linux, `run.sh`, run with
  `NO_AT_BRIDGE=1`) builds method calls with the bridge's own writer, feeds them
  through `atspi_receive`, and parses the replies. It checks the application's
  window, the frame's title, children in order, roles (including PASSWORD_TEXT),
  state bits, names, text, the masked password, actions, requests with their
  values, and unknown, republished and closed paths.
- `ui_accessibility` now also checks the `secret` bit.

End to end, against the gallery (`examples/ui`), with a real client. These are the
checks run for D1602 and D1603:

- **Windows:** the .NET `System.Windows.Automation` client in PowerShell. Walk
  `ControlViewWalker` from `AutomationElement.FromHandle`; invoke "Filled" (the
  press counter goes 0 → 1); `SetFocus` on "Outlined" (a compiled
  `AddAutomationFocusChangedEventHandler` sees it); select the Fields tab; toggle a
  checkbox Off → On; `ValuePattern.SetValue("héllo")` round-trips; the Password
  field reads `*******` with `IsPassword=True`.
- **Linux (WSLg):** `python3-dbus` on the accessibility bus. Find the application
  among the registry's children by `ToolkitName == "neper"`; walk `GetChildren`;
  `DoAction(0)` on "Filled" (the counter goes 0 → 1); `GrabFocus` (a
  `StateChanged("focused", 1)` signal arrives for the node's path);
  `SetTextContents("héllo")`, then `GetText` returns it with CharacterCount 5; the
  password entry has role 40 and text `*******`. Paths are stable at rest (0
  changed across repeated walks of 141 nodes).

With a screen reader: start Narrator (Ctrl+Win+Enter) or NVDA and run the gallery
on Windows; run it under Orca in a Linux desktop session. Tab moves focus and each
control is announced with its name and role.

## Not yet

- **macOS.** NSAccessibility is not written. `accessibility_publish` answers
  `Unsupported` on hosts without a bridge.
- **Change events beyond focus and structure.** A value, name or live-region change
  raises no event, so a screen reader reads a changed value when it next asks for
  it, not when it changes.
- **Ranges and selection containers.** There is no RangeValue or Value interface
  for sliders and progress bars, and no Selection or Table interface on containers.
- **AT-SPI extents** are window-relative in every coordinate space. The window's
  position on screen is not asked of X. Text answers every granularity with the
  whole text.
- **Identity.** An element is its slot plus the generation last handed out. A
  client that holds an element whose slot was reused reaches the new node. Slots
  past 16384 and nodes past 8192 per window are not published.
