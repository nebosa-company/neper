# IconButton

An icon button runs an action, or switches an option, with an icon alone, for compact places where the icon is well understood: toolbars, app bars, list rows and field ends.

## Anatomy
1. Container: a 40 circle (`radius-full`); transparent for standard.
2. Icon: `icon-md` 24 (18 at the 24 and 32 sizes), centred.
3. State layer: the icon colour over the container.
4. Focus ring: 3 px `focus-ring`, 2 px outside.
5. Optional badge on the icon.
6. Tooltip: the button's name, shown on hover and long press.

## Variants and when to use
| Variant | Container | Icon | Use for |
|---|---|---|---|
| Standard | none | `on-surface-variant` | Most icon buttons: app bars, toolbars, row actions, a field's clear button. |
| Filled | `primary` | `on-primary` | The one important icon-only action in a region: Run, Send. |
| Tonal | `secondary-container` | `on-secondary-container` | A medium-emphasis action beside a filled one, or a lone action on a busy ground. |
| Outlined | 1 px `outline` | `on-surface-variant` | Secondary actions that need an edge: pagination, a toolbar on media. |

Toggle forms (the button keeps a selected state):
| Variant | Off | On |
|---|---|---|
| Standard | outline icon, `on-surface-variant` | filled icon, `primary` |
| Filled | `surface-container-highest`, `primary` icon | `primary`, `on-primary` icon |
| Tonal | `surface-container-highest`, `on-surface-variant` | `secondary-container`, `on-secondary-container`, filled icon |
| Outlined | 1 px `outline`, `on-surface-variant` | `inverse-surface`, `inverse-on-surface`, no edge |

Use Button when a word is clearer than the icon, Toggle button for a labelled on/off action, Segmented button for one of a few options, and the FAB for a screen's main creation action.

## Specs
| | XS (density -2) | Small (density -1) | Default | Large |
|---|---|---|---|---|
| Container | `control-xs` 24, `radius-xs` | `control-sm` 32 | `control-md` 40 | `control-xl` 56 |
| Icon | `icon-sm` 18 | `icon-sm` 18 | `icon-md` 24 | 28 |
| Target | pads to `target-pointer` 32 | 32 | pads to `target-touch` 48 on touch | 56 |
| Use | tab close, table rows, dense tool windows | desktop toolbars and app bars | touch, default | a lone action in an empty state or media |

| Part | Value |
|---|---|
| Gap between icon buttons | `space-1` 4 in toolbars, `space-2` 8 elsewhere; targets may not overlap |
| Outline | 1 px `outline` (disabled: `on-surface` 12%) |
| Badge | anchored to the icon: count at top -2, end -12 |
| Tooltip | plain tooltip, `space-1` below (above when there is no room), after `duration-short-4` hover; includes the shortcut |

## States
- Hover: state layer at `state-hover` in the icon colour; the tooltip after 500 ms.
- Focus: `state-focus` layer and the ring (keyboard only).
- Pressed: `state-pressed` layer; ripple on touch hosts, bounded to the circle.
- Selected (toggle): the "on" colours and the filled icon; the icon change carries the state without colour.
- Disabled: icon `on-surface` 38%; filled and tonal containers `on-surface` 12%; outlined edge 12%; not focusable, no tooltip, except in toolbars where disabled buttons stay focusable so their tooltip can say why.
- Loading: the icon is replaced by an 18 circular progress in the icon colour.

## Behaviour
- Press on release inside the bounds; Enter and Space press when focused.
- Toggle buttons flip on press and report the new state at once; the caller may reject it and the button returns.
- In a toolbar the group is one Tab stop with arrow keys between buttons (roving focus), Home and End to the ends.
- Long press on touch shows the tooltip; it never fires the action.
- The icon morph for a toggle cross-fades in `duration-short-3` with `ease-standard`.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | Small (32) in command bars with `radius-sm` squares are acceptable only in title bars; keep circles elsewhere; tooltips show the shortcut ("Refresh (F5)"). |
| macOS | Small (32) in toolbars; standard variant with no container at rest, as NSToolbar items; tooltips after the system delay; toolbar buttons can be customised when the app opts in. |
| Linux | Small (32); GNOME header bars use flat (standard) buttons; KDE toolbars show text beside icons when the desktop setting asks for it. |
| Android | Default (40 with a 48 target); ripple; tooltips on long press. |
| iOS | Default with a 44 pt target; no ripple; standard variant in navigation bars tinted `primary`, as UIBarButtonItem. |
| Web | A real `<button>` with `aria-label`; `aria-pressed` for toggles; `:focus-visible` ring. |

## Accessibility
- Role Button with the Press action, named by the label (never the icon's file name): "Delete build", "Show sidebar".
- Toggles report Pressed (on/off) and keep the same name; don't rename "Mute" to "Unmute".
- Badges fold into the name: "Notifications, 3 unread".
- Target 48 on touch hosts, 32 with a fine pointer, even at the 24 size.
- Contrast: icon 3:1 against its container or ground; `on-surface-variant` on `surface` meets 4.5:1.
- Disabled toolbar buttons expose Disabled and their reason as the description.
- Reduced motion: no ripple, no icon morph.

## Content
- The name starts with a verb unless it toggles a view: "Delete build", "Refresh", "Sidebar".
- Tooltips repeat the name and add the shortcut in parentheses.
- If three people would name the icon differently, use a Button with a word.

## e.ui today
`control.icon_button` is the Button pressable (`style.resolve` Filled, Outlined or Plain) with a texture in place of the label, sized `control_height - 2 × space-xs`, padding `space-xs` by `space-md`, `radius-md`. To reach this design:
- Make it a 40 circle (24, 32 and 56 sizes too); today it is 48 wide by 32 tall with `radius-md` corners.
- Tint the icon with the variant's content colour; the resolved foreground is never applied, so it does not turn `on-primary` on a filled button.
- Add the tonal variant and map Plain to standard.
- Add the toggle forms (a `selected` flag with the filled icon), or fold `toggle_button`'s icon case in here.
- Draw state layers and the focus ring (`pressable_states` drops `focus_ring`), and add the tooltip from `label`.
