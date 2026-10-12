// The conflict review as markup (L037), after `renderConflictReview` of appdor's `src/offline/conflict-review.js`: a
// review `{items: [{id, recordId, kind, fields, choices, contestedFields, mergeBlockedBy}]}` (what
// `e.algo.offline.build_conflict_review` answers) becomes one `<section>` per conflict -- the record's title, a table of
// the fields where the two sides differ (mine, theirs, the contested ones marked) or a note that the server deleted the
// record, one button per choice, which fields are contested and why a merge is not offered. An empty review is the
// empty text.
//
// Every text goes through `escape_html` and, where it is a sentence, the host's translator (`run(ctx, key, variable)`:
// the catalogue key and the one variable the sentence names -- the record id or the contested field names). A value is
// shown as its text (a string as it is, anything else as JSON), cut after 120 UTF-16 code units with `…`, and an absent
// one as `—`.
//
// `escape_html` is what the DOM's `textContent` / `innerHTML` pair does to text: `&`, `<`, `>` and the no-break space
// as named references, then `"` and `'` as numeric ones.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.algo.writeback as wb
use e.fmt.json as json
use e.mem
use e.str

// The text made safe for markup, in text and quoted attribute alike.
fn escape_html(a: *mem.Arena, s: str) -> str {
    let (b, e) = str.builder(a, s.len + s.len / 4usize + 16usize)
    if e != ok { ret s }
    var out = b
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 38u8 {
            let p = str.push(&out, "&amp;")
        } else if c == 60u8 {
            let p = str.push(&out, "&lt;")
        } else if c == 62u8 {
            let p = str.push(&out, "&gt;")
        } else if c == 34u8 {
            let p = str.push(&out, "&quot;")
        } else if c == 39u8 {
            let p = str.push(&out, "&#39;")
        } else if c == 194u8 && at + 1usize < s.len && s[at + 1usize] == 160u8 {
            let p = str.push(&out, "&nbsp;")
            at += 1usize
        } else {
            let p = str.push_byte(&out, c)
        }
        at += 1usize
    }
    ret str.done(&out)
}

// The text cut after `limit` UTF-16 code units, and whether it was cut.
fn cut_units(s: str, limit: usize) -> (str, bool) {
    var units = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        var width = 1usize
        var units_here = 1usize
        if c >= 240u8 {
            width = 4usize
            units_here = 2usize
        } else if c >= 224u8 {
            width = 3usize
        } else if c >= 192u8 {
            width = 2usize
        }
        if units + units_here > limit { ret (s[0usize..at], true) }
        units += units_here
        at += width
    }
    ret (s, false)
}

fn units_over(s: str, limit: usize) -> bool {
    var units = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c >= 240u8 {
            units += 2usize
            at += 4usize
        } else if c >= 224u8 {
            units += 1usize
            at += 3usize
        } else if c >= 192u8 {
            units += 1usize
            at += 2usize
        } else {
            units += 1usize
            at += 1usize
        }
        if units > limit { ret true }
    }
    ret false
}

// How a field value reads in the table.
fn show(a: *mem.Arena, v: json.Value, present: bool) -> str {
    if !present { ret "\xE2\x80\x94" }
    var text = ""
    let (s, is_text) = ir.string_of(v)
    if is_text {
        text = s
    } else {
        text = syncjob.plain(a, v)
    }
    if units_over(text, 120usize) {
        let (head, cut) = cut_units(text, 120usize)
        ret sync.cat(a, head, "\xE2\x80\xA6")
    }
    ret text
}

fn element_text(a: *mem.Arena, v: json.Value) -> str {
    if ir.is_null(v) { ret "" }
    ret wb.js_string(a, v, true)
}

fn attribute(a: *mem.Arena, s: str) -> str { ret escape_html(a, s) }

fn say(a: *mem.Arena, translate: *const syncjob.Translate, key: str, variable: str) -> str {
    ret escape_html(a, translate.run(translate.ctx, key, variable))
}

fn rows_markup(a: *mem.Arena, item: json.Value) -> str {
    var out = ""
    let fields = sync.items(ir.value_of(item, "fields"))
    var at = 0usize
    while at < fields.len {
        let f = fields[at]
        at += 1usize
        out = sync.cat(a, out, "\n    <tr class=\"border-b border-subtle")
        if ir.truthy(ir.value_of(f, "contested")) { out = sync.cat(a, out, " bg-warn-subtle") }
        out = sync.cat(a, out, "\">\n      <td class=\"py-1 pr-3 font-medium\">")
        out = sync.cat(a, out, escape_html(a, wb.js_string(a, ir.value_of(f, "name"), true)))
        out = sync.cat(a, out, "</td>\n      <td class=\"py-1 pr-3\">")
        let (mine, has_mine) = sync.get(f, "mine")
        out = sync.cat(a, out, escape_html(a, show(a, mine, has_mine)))
        out = sync.cat(a, out, "</td>\n      <td class=\"py-1\">")
        let (theirs, has_theirs) = sync.get(f, "theirs")
        out = sync.cat(a, out, escape_html(a, show(a, theirs, has_theirs)))
        out = sync.cat(a, out, "</td>\n    </tr>")
    }
    ret out
}

fn choice_button(a: *mem.Arena, translate: *const syncjob.Translate, item_id: str, choice: str) -> str {
    var out = sync.cat(a, "<button type=\"button\" data-conflict-choice=\"", attribute(a, choice))
    out = sync.cat(a, out, "\" data-conflict-id=\"")
    out = sync.cat(a, out, attribute(a, item_id))
    out = sync.cat(a, out, "\"\n      class=\"px-2 py-1 rounded-control border border-strong text-xs hover:bg-hover\">")
    out = sync.cat(a, out, say(a, translate, sync.cat(a, "offline.conflict.", choice), ""))
    ret sync.cat(a, out, "</button>")
}

// The review as markup; the empty text for a review with no items.
fn render_conflict_review(a: *mem.Arena, review: json.Value, translate: *const syncjob.Translate) -> str {
    let items = sync.items(ir.value_of(review, "items"))
    if items.len == 0usize { ret "" }
    var out = ""
    var at = 0usize
    while at < items.len {
        let item = items[at]
        at += 1usize
        let id = escape_html(a, wb.js_string(a, ir.value_of(item, "id"), true))
        let record_id = wb.js_string(a, ir.value_of(item, "recordId"), true)
        out = sync.cat(a, out, "\n    <section class=\"rounded-control border border-subtle p-3 mb-3\" data-conflict-item=\"")
        out = sync.cat(a, out, id)
        out = sync.cat(a, out, "\">\n      <p class=\"text-sm font-medium mb-2\">")
        out = sync.cat(a, out, say(a, translate, "offline.conflict.record", record_id))
        out = sync.cat(a, out, "</p>\n      ")
        if wb.member_is(item, "kind", "record-deleted-on-server") {
            out = sync.cat(a, out, "<p class=\"text-xs text-danger mb-2\">")
            out = sync.cat(a, out, say(a, translate, "offline.conflict.deleted", ""))
            out = sync.cat(a, out, "</p>")
        } else {
            out = sync.cat(a, out, "<table class=\"w-full text-left text-xs mb-2\">\n             <thead><tr class=\"text-muted\">\n               <th class=\"py-1 pr-3\">")
            out = sync.cat(a, out, say(a, translate, "offline.conflict.field", ""))
            out = sync.cat(a, out, "</th>\n               <th class=\"py-1 pr-3\">")
            out = sync.cat(a, out, say(a, translate, "offline.conflict.mine", ""))
            out = sync.cat(a, out, "</th>\n               <th class=\"py-1\">")
            out = sync.cat(a, out, say(a, translate, "offline.conflict.theirs", ""))
            out = sync.cat(a, out, "</th>\n             </tr></thead>\n             <tbody>")
            out = sync.cat(a, out, rows_markup(a, item))
            out = sync.cat(a, out, "</tbody>\n           </table>")
        }
        out = sync.cat(a, out, "\n      <div class=\"flex flex-wrap gap-2\">")
        let choices = sync.items(ir.value_of(item, "choices"))
        var c = 0usize
        while c < choices.len {
            out = sync.cat(a, out, choice_button(a, translate, wb.js_string(a, ir.value_of(item, "id"), true), wb.js_string(a, choices[c], true)))
            c += 1usize
        }
        out = sync.cat(a, out, "</div>\n      ")
        let contested = sync.items(ir.value_of(item, "contestedFields"))
        if contested.len > 0usize {
            var joined = ""
            var k = 0usize
            while k < contested.len {
                if k > 0usize { joined = sync.cat(a, joined, ", ") }
                joined = sync.cat(a, joined, element_text(a, contested[k]))
                k += 1usize
            }
            out = sync.cat(a, out, "<p class=\"text-2xs text-warn mt-1\">")
            out = sync.cat(a, out, say(a, translate, "offline.conflict.contested", joined))
            out = sync.cat(a, out, "</p>")
        }
        out = sync.cat(a, out, "\n      ")
        let blocked = ir.value_of(item, "mergeBlockedBy")
        if ir.truthy(blocked) {
            out = sync.cat(a, out, "<p class=\"text-2xs text-muted mt-1\">")
            out = sync.cat(a, out, say(a, translate, sync.cat(a, "offline.conflict.blocked.", wb.js_string(a, blocked, true)), ""))
            out = sync.cat(a, out, "</p>")
        }
        out = sync.cat(a, out, "\n    </section>")
    }
    ret out
}
