# Browser

The browser control is a web browser in a window: a tab strip, back, forward and reload, an omnibox, a bookmark toggle and the page, over the Neper engine (`e.web.page`) and its shell model (`e.web.shell`). It is the one control that hosts other documents.

## Anatomy
1. Tab strip: one tab per open page, each with its title and a close button, and a new-tab button. Each tab owns an arena and its own session history.
2. Navigation buttons: back, forward and reload (back and forward are disabled when the history has no entry in that direction).
3. Omnibox: one text field that takes an address or a search.
4. Bookmark toggle: filled when the current address is bookmarked.
5. Page: the rendered document, laid out and painted by the engine into the window's surface.

## Omnibox rules
| You type | The browser opens |
|---|---|
| Nothing | `about:blank` |
| An address with a scheme | that address |
| A host name or address with no spaces | `https://` plus the text; `http://` for `localhost` and numeric addresses |
| Anything else | a web search for the text |

## Special pages
| Address | Shows |
|---|---|
| `about:blank` | an empty new-tab page |
| `about:history` | the visit log, newest first |
| `about:bookmarks` | the bookmarks, oldest first |

A page that fails to load leaves an error page that gives the reason in words: the server could not be found, the connection failed, the address is not valid, the scheme or port is not supported, or the server redirected too many times.

## Behaviour
- A navigation rewinds the tab's arena and loads the new page into it, so a tab's memory is bounded by its largest page, not by how long it has been open.
- Each tab keeps its own session history; back and forward move through it.
- Visits and bookmarks are kept in a profile file, read at start and written on exit.
- One shared network client loads every tab and follows redirects up to a limit.

## States
- Back and forward are enabled only when the tab's history has an entry in that direction.
- Error: the error page replaces the document.

## Accessibility
Requirements for the control; the first two follow the Tabs and Button specifications.
- The tab strip is a tab list; each tab has its title as its name and exposes its selected state.
- Navigation buttons and the bookmark toggle have names ("Back", "Forward", "Reload", "Bookmark this page"), and the toggle exposes a pressed state.
- The omnibox is a text field named "Address and search".
- Page content must reach assistive technology through the engine's document tree, not as an image. This is not built yet.

## e.ui today
The shell model is complete and tested without a window (`e.web.shell`); the windowed app is a thin layer over it (`examples/browser/main.e`). Engine conformance is tracked against the web platform tests and is not complete.
