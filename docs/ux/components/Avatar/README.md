# Avatar

An avatar identifies a person, team or workspace with their picture, their initials or a fallback icon in a small disc.

## Anatomy
1. Container: a circle (`radius-full`) for people, a `radius-sm` square for teams, workspaces and bots.
2. Content: a photo (cover-fitted), one or two initials, or the `person` / `folder` icon.
3. Optional presence indicator: a 12 px mark at the bottom end, ringed 2 px in the ground colour.
4. Optional state layer and focus ring when it opens a profile.

## Variants and when to use
| Variant | Content | Use for |
|---|---|---|
| Photo | the picture | People who set one. |
| Initials | 1-2 letters on a tonal container | People without a photo. The container is chosen from the name (a stable hash) among `primary-container`, `secondary-container`, `tertiary-container`. |
| Icon | `person` on `surface-container-highest` | Unknown or deleted people, guests. |
| Square | initials or icon, `radius-sm` | Teams, workspaces, organisations, bots and service accounts. |
| Group | 2-3 avatars overlapped plus a count | Who is on a project or in a thread. |

Use Icon for objects, Image for pictures that are not identities, and Chip with an avatar for a removable person in a field.

## Specs
| Size | 24 | 32 | 40 (default) | 56 | 72 |
|---|---|---|---|---|---|
| Use | dense lists, chips | desktop lists, groups | lists, comments | profile headers, cards | profile page |
| Initials type | 11 / 600 | 13 / 600 | `title-medium` 16 / 600 | 22 / 400 | 28 / 400 |
| Icon | 16 | 18 | 24 | 36 | 36 |
| Presence | 8 | 10 | 12 | 14 | 16 |

| Part | Value |
|---|---|
| Initials colours | `primary-container`/`on-primary-container`, `secondary-container`/`on-secondary-container`, `tertiary-container`/`on-tertiary-container` |
| Fallback | `surface-container-highest` with `on-surface-variant` icon |
| Photo | cover-fitted, centred on the face if known; a 1 px `outline-variant` inner ring on light photos is not used (the ground is enough) |
| Presence: online | filled `success` disc |
| Presence: away | `warning` ring, 2.5 px, hollow |
| Presence: busy | `error` disc with an `on-error` bar |
| Presence: offline | `outline` ring, 2 px, hollow |
| Presence ring | 2 px in the ground colour (`surface` or the container it sits on) |
| Group | overlap 8 (25% at 32), each ringed 2 px in the ground; max 3 faces, then a neutral "+n" |
| Hover / pressed | `on-surface` layer at `state-hover` / `state-pressed` over the disc |
| Target | the avatar pads to `target-pointer` 32 / `target-touch` 48 |

## States
- Rest; Loading: the initials version shows until the photo decodes, then cross-fades in `duration-short-3`.
- Hover, pressed (pressable): state layer over the disc.
- Focus: the focus ring, 3 px `focus-ring`, 2 px outside the circle.
- Disabled: not used; show a deactivated account with the icon fallback and "Deactivated" in the name.
- Error (photo failed): falls back to initials silently.

## Behaviour
- Pressable avatars open the profile or a profile card (a Popover on desktop hover after `duration-medium-1`, a sheet on touch).
- Initials: the first letter of the first and last names in the person's script; one letter for single-word names; never lowercase Latin initials.
- The colour for initials is a stable hash of the account id, never random per render.
- Groups: pressing the group opens the full list; pressing a face in a group is not a separate target below 40.
- Presence updates in place with a `duration-short-3` cross-fade; reduced motion swaps.

## Platform adaptation
| Host | What changes |
|---|---|
| Windows | 32 default in desktop lists; use the account picture from the Windows account only for the signed-in user. |
| macOS | 32 default in sidebars and lists; contacts pictures from the address book when the user allows it. |
| Linux | 32 default; the user's picture from AccountsService for the signed-in user. |
| Android | 40 default; 48 targets. |
| iOS | 40 default; iOS contact-style monogram gradient is not used, keep the tonal containers. |
| Web | 40 default; `<img alt>` for photos with the initials as fallback on error. |

## Accessibility
- Next to the person's name: decorative, hidden from the tree, so the name is not read twice.
- Alone: role Image named by the person, with presence appended ("Ada Lovelace, online").
- Pressable: role Button named "Open profile of Ada Lovelace" or the name when the context makes the action clear.
- Groups: one node, "Ada Lovelace, Mina Kato, Jon Reyes and 4 others".
- Presence is never colour alone: each status has a different shape and is in the name.
- Contrast: initials 4.5:1 on their container; the presence mark 3:1 against the ring.
- Reduced motion: no cross-fades.

## Content
- Initials in capitals, no dots: "AL".
- Overflow count as "+4", not "4 more".
- Presence words: "Online", "Away", "Do not disturb", "Offline".

## e.ui today
`control.avatar` clips a caller texture, fit `.Cover`, to a disc of `size` on `SurfaceVariant`, as an Image-role node named `label`. To reach this design:
- Add the initials fallback on a tonal container chosen from a stable hash; an avatar with no picture is an empty disc today.
- Add the icon fallback and the square team variant.
- Add the presence indicator with its four shapes, and put presence in the node's name.
- Fix the token sizes (24, 32, 40, 56, 72) instead of a free `size`.
- Hide the avatar from the tree when it sits beside the name (empty label), as `image` does; add a pressable form with state layers and the focus ring.
