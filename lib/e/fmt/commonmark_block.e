// Block parsing for e.fmt.commonmark: a port of cmark-gfm's blocks.c line by line -- containers that
// match the start of each line, new blocks that open, text added to the innermost open block -- with the
// GFM table and task-list extensions (table.c, tasklist.c) inlined. Inlines are parsed after the last line.

use e.mem
use e.str
use e.fmt.commonmark_text as ct
use e.fmt.commonmark_tree as tr
use e.fmt.commonmark_inline as ci

type Cell = struct { start_offset: i32, end_offset: i32, internal_offset: i32, buf: str }

type Row = struct { n: usize, cells: []Cell, paragraph_offset: i32 }

type ListData = struct { list_type: u8, bullet: u8, delim: u8, start: i32 }

fn ix(i: i32) -> usize { ret usize(i) }

fn lc(d: *const tr.Doc, i: i32) -> u8 {
    if i < 0i32 { ret 0u8 }
    ret ct.pk(d.line, ix(i))
}

// The line as the scanners see it: up to its current length.
fn inp(d: *const tr.Doc) -> str {
    if d.llen > d.line.len { ret d.line }
    ret d.line[0usize..d.llen]
}

fn is_blank_from(s: str, offset: usize) -> bool {
    var i = offset
    while i < s.len {
        let c = s[i]
        if c == 13u8 || c == 10u8 { ret true }
        if c != 32u8 && c != 9u8 { ret false }
        i += 1usize
    }
    ret true
}

fn accepts_lines(kind: u8) -> bool { ret kind == tr.K_PARAGRAPH || kind == tr.K_HEADING || kind == tr.K_CODE_BLOCK }

fn contains_inlines(kind: u8) -> bool { ret kind == tr.K_PARAGRAPH || kind == tr.K_HEADING || kind == tr.K_CELL }

fn add_line(d: *tr.Doc, node: i32) {
    if d.partial_tab {
        d.offset += 1i32
        var n = 4i32 - d.column % 4i32
        while n > 0i32 {
            tr.content_putc(d, node, 32u8)
            n -= 1i32
        }
    }
    let ins = inp(d)
    if ix(d.offset) < ins.len { tr.content_put(d, node, ins[ix(d.offset)..ins.len]) }
}

// The length of `s` after cutting its blank tail (cmark's remove_trailing_blank_lines).
fn trimmed_blank_lines(s: str) -> usize {
    var i = i32(s.len) - 1i32
    while i >= 0i32 {
        let c = s[ix(i)]
        if c != 32u8 && c != 9u8 && !ct.is_line_end(c) { break }
        i -= 1i32
    }
    if i < 0i32 { ret 0usize }
    var k = ix(i)
    while k < s.len {
        if ct.is_line_end(s[k]) { ret k }
        k += 1usize
    }
    ret s.len
}

fn ends_with_blank_line(d: *tr.Doc, node: i32) -> bool {
    let n = ix(node)
    if d.nodes[n].last_checked { ret d.nodes[n].last_blank }
    if (d.nodes[n].kind == tr.K_LIST || d.nodes[n].kind == tr.K_ITEM) && d.nodes[n].last != tr.NIL {
        d.nodes[n].last_checked = true
        ret ends_with_blank_line(d, d.nodes[n].last)
    }
    d.nodes[n].last_checked = true
    ret d.nodes[n].last_blank
}

// Cuts link reference definitions off the front of a paragraph; true when text remains.
fn resolve_references(d: *tr.Doc, b: i32) -> bool {
    var rest = tr.content(d, b)
    while rest.len > 0usize && rest[0usize] == 91u8 {
        let pos = ci.parse_reference(d, rest)
        if pos == 0usize { break }
        rest = rest[pos..rest.len]
    }
    tr.content_set(d, b, rest)
    ret !is_blank_from(rest, 0usize)
}

fn finalize(d: *tr.Doc, b: i32) -> i32 {
    let n = ix(b)
    let parent = d.nodes[n].parent
    d.nodes[n].open = false
    let kind = d.nodes[n].kind
    if d.line.len == 0usize {
        d.nodes[n].el = d.line_number
        d.nodes[n].ec = d.last_line_len
    } else {
        if kind == tr.K_DOCUMENT || (kind == tr.K_CODE_BLOCK && d.nodes[n].fenced) || (kind == tr.K_HEADING && d.nodes[n].setext) {
            d.nodes[n].el = d.line_number
            var ec = i32(d.line.len)
            if ec > 0i32 && d.line[ix(ec) - 1usize] == 10u8 { ec -= 1i32 }
            if ec > 0i32 && d.line[ix(ec) - 1usize] == 13u8 { ec -= 1i32 }
            d.nodes[n].ec = ec
        } else {
            d.nodes[n].el = d.line_number - 1i32
            d.nodes[n].ec = d.last_line_len
        }
    }
    if kind == tr.K_PARAGRAPH {
        let has = resolve_references(d, b)
        if !has { tr.unlink(d, b) }
    } else {
        if kind == tr.K_CODE_BLOCK {
            let c = tr.content(d, b)
            if !d.nodes[n].fenced {
                let l = trimmed_blank_lines(c)
                var text = ""
                if l > 0usize { text = c[0usize..l] }
                var bb = ct.buf_new(d.a, text.len + 2usize)
                ct.put(&bb, text)
                ct.putc(&bb, 10u8)
                if bb.failed { d.failed = true }
                d.nodes[n].lit = ct.view(&bb)
            } else {
                var pos = 0usize
                while pos < c.len && !ct.is_line_end(c[pos]) { pos += 1usize }
                var tmp = ct.buf_new(d.a, pos + 2usize)
                ct.unescape_html(&tmp, c[0usize..pos])
                if tmp.failed { d.failed = true }
                let trimmed = ci.trim_str(ct.view(&tmp))
                var tb = ct.buf_new(d.a, trimmed.len + 2usize)
                ct.put(&tb, trimmed)
                ct.unescape_backslashes(&tb, 0usize)
                if tb.failed { d.failed = true }
                d.nodes[n].info = ct.view(&tb)
                if pos < c.len && c[pos] == 13u8 { pos += 1usize }
                if pos < c.len && c[pos] == 10u8 { pos += 1usize }
                d.nodes[n].lit = c[pos..c.len]
            }
        } else {
            if kind == tr.K_HTML_BLOCK {
                d.nodes[n].lit = tr.content(d, b)
            } else {
                if kind == tr.K_LIST {
                    d.nodes[n].tight = true
                    var item = d.nodes[n].first
                    while item != tr.NIL {
                        if d.nodes[ix(item)].last_blank && d.nodes[ix(item)].next != tr.NIL {
                            d.nodes[n].tight = false
                            break
                        }
                        var sub = d.nodes[ix(item)].first
                        while sub != tr.NIL {
                            if (d.nodes[ix(item)].next != tr.NIL || d.nodes[ix(sub)].next != tr.NIL) && ends_with_blank_line(d, sub) {
                                d.nodes[n].tight = false
                                break
                            }
                            sub = d.nodes[ix(sub)].next
                        }
                        if !d.nodes[n].tight { break }
                        item = d.nodes[ix(item)].next
                    }
                }
            }
        }
    }
    ret parent
}

fn add_child(d: *tr.Doc, parent_in: i32, kind: u8, start_column: i32) -> i32 {
    var parent = parent_in
    while !tr.can_contain(d, parent, kind) { parent = finalize(d, parent) }
    let child = tr.new_node(d, kind)
    let c = ix(child)
    d.nodes[c].open = true
    d.nodes[c].sl = d.line_number
    d.nodes[c].sc = start_column
    d.nodes[c].el = d.line_number
    tr.append_child(d, parent, child)
    ret child
}

// A list marker at `pos`: the length (0 when none) and the list's fields.
fn parse_list_marker(d: *const tr.Doc, pos_in: i32, interrupts: bool) -> (i32, ListData) {
    var ld: ListData = zero
    var pos = pos_in
    let startpos = pos
    var c = lc(d, pos)
    if c == 42u8 || c == 45u8 || c == 43u8 {
        pos += 1i32
        if !ct.is_space(lc(d, pos)) { ret (0i32, ld) }
        if interrupts {
            var i = pos
            while ct.is_blank_char(lc(d, i)) { i += 1i32 }
            if lc(d, i) == 10u8 { ret (0i32, ld) }
        }
        ld.list_type = 1u8
        ld.bullet = c
        ld.start = 0i32
        ld.delim = 0u8
    } else {
        if ct.is_digit(c) {
            var start = 0i32
            var digits = 0i32
            while true {
                start = 10i32 * start + i32(lc(d, pos) - 48u8)
                pos += 1i32
                digits += 1i32
                if !(digits < 9i32 && ct.is_digit(lc(d, pos))) { break }
            }
            if interrupts && start != 1i32 { ret (0i32, ld) }
            c = lc(d, pos)
            if c == 46u8 || c == 41u8 {
                pos += 1i32
                if !ct.is_space(lc(d, pos)) { ret (0i32, ld) }
                if interrupts {
                    var i = pos
                    while ct.is_blank_char(lc(d, i)) { i += 1i32 }
                    if ct.is_line_end(lc(d, i)) { ret (0i32, ld) }
                }
                ld.list_type = 2u8
                ld.bullet = 0u8
                ld.start = start
                if c == 46u8 { ld.delim = 1u8 } else { ld.delim = 2u8 }
            } else {
                ret (0i32, ld)
            }
        } else {
            ret (0i32, ld)
        }
    }
    ret (pos - startpos, ld)
}

fn lists_match(d: *const tr.Doc, list: i32, ld: *const ListData) -> bool {
    let n = ix(list)
    ret d.nodes[n].list_type == ld.list_type && d.nodes[n].delim == ld.delim && d.nodes[n].bullet == ld.bullet
}

// Thematic break at `offset`: the length, or 0 (and where the scan gave up).
fn scan_thematic_break(d: *tr.Doc, offset: i32) -> i32 {
    var i = offset
    let c = lc(d, i)
    if !(c == 42u8 || c == 95u8 || c == 45u8) {
        d.thematic_kill = i
        ret 0i32
    }
    var count = 1i32
    var nextc = 0u8
    while true {
        i += 1i32
        nextc = lc(d, i)
        if nextc == 0u8 { break }
        if nextc == c {
            count += 1i32
        } else {
            if nextc != 32u8 && nextc != 9u8 { break }
        }
    }
    if count >= 3i32 && (nextc == 13u8 || nextc == 10u8) { ret (i - offset) + 1i32 }
    d.thematic_kill = i
    ret 0i32
}

fn find_first_nonspace(d: *tr.Doc) {
    var chars_to_tab = 4i32 - d.column % 4i32
    if d.first_nonspace <= d.offset {
        d.first_nonspace = d.offset
        d.first_nonspace_col = d.column
        while true {
            let c = lc(d, d.first_nonspace)
            if c == 32u8 {
                d.first_nonspace += 1i32
                d.first_nonspace_col += 1i32
                chars_to_tab -= 1i32
                if chars_to_tab == 0i32 { chars_to_tab = 4i32 }
            } else {
                if c == 9u8 {
                    d.first_nonspace += 1i32
                    d.first_nonspace_col += chars_to_tab
                    chars_to_tab = 4i32
                } else {
                    break
                }
            }
        }
    }
    d.indent = d.first_nonspace_col - d.column
    d.blank = ct.is_line_end(lc(d, d.first_nonspace))
}

fn advance_offset(d: *tr.Doc, count_in: i32, columns: bool) {
    var count = count_in
    while count > 0i32 && lc(d, d.offset) != 0u8 {
        let c = lc(d, d.offset)
        if c == 9u8 {
            let chars_to_tab = 4i32 - d.column % 4i32
            if columns {
                d.partial_tab = chars_to_tab > count
                var adv = count
                if chars_to_tab < adv { adv = chars_to_tab }
                d.column += adv
                if !d.partial_tab { d.offset += 1i32 }
                count -= adv
            } else {
                d.partial_tab = false
                d.column += chars_to_tab
                d.offset += 1i32
                count -= 1i32
            }
        } else {
            d.partial_tab = false
            d.offset += 1i32
            d.column += 1i32
            count -= 1i32
        }
    }
}

fn last_child_is_open(d: *const tr.Doc, container: i32) -> bool {
    let lcn = d.nodes[ix(container)].last
    ret lcn != tr.NIL && d.nodes[ix(lcn)].open
}

// --- Table helpers.

fn unescape_pipes(d: *tr.Doc, s: str) -> str {
    var b = ct.buf_new(d.a, s.len + 1usize)
    var r = 0usize
    while r < s.len {
        if s[r] == 92u8 && ct.pk(s, r + 1usize) == 124u8 { r += 1usize }
        ct.putc(&b, s[r])
        r += 1usize
    }
    if b.failed { d.failed = true }
    ret ct.view(&b)
}

// One table row out of `string`, or none: cells in order, with where the row's own text begins.
fn row_from_string(d: *tr.Doc, string: str) -> (bool, Row) {
    var row: Row = zero
    let len = i32(string.len)
    let (cells, e) = mem.alloc[Cell](d.a, string.len + 2usize)
    if e != ok {
        d.failed = true
        ret (false, row)
    }
    row.cells = cells
    var offset = i32(ct.scan_table_cell_end(string, 0usize))
    var expect_more = true
    while offset < len && expect_more {
        let cell_matched = i32(ct.scan_table_cell(string, ix(offset)))
        let pipe_matched = i32(ct.scan_table_cell_end(string, ix(offset + cell_matched)))
        if cell_matched > 0i32 || pipe_matched > 0i32 {
            let raw = unescape_pipes(d, string[ix(offset)..ix(offset + cell_matched)])
            var c: Cell = zero
            c.buf = ci.trim_str(raw)
            c.start_offset = offset
            c.end_offset = offset + cell_matched - 1i32
            c.internal_offset = 0i32
            while c.start_offset > row.paragraph_offset && string[ix(c.start_offset) - 1usize] != 124u8 {
                c.start_offset -= 1i32
                c.internal_offset += 1i32
            }
            row.cells[row.n] = c
            row.n += 1usize
        }
        offset += cell_matched + pipe_matched
        if pipe_matched > 0i32 {
            expect_more = true
        } else {
            let row_end = i32(ct.scan_table_row_end(string, ix(offset)))
            offset += row_end
            if row_end > 0i32 && offset != len {
                row.paragraph_offset = offset
                row.n = 0usize
                offset += i32(ct.scan_table_cell_end(string, ix(offset)))
                expect_more = true
            } else {
                expect_more = false
            }
        }
    }
    if offset != len || row.n == 0usize { ret (false, row) }
    ret (true, row)
}

fn set_cell_content(d: *tr.Doc, node: i32, s: str) {
    tr.content_set(d, node, s)
}

// Opens a table when the current paragraph is a header row and this line its delimiter row.
fn try_opening_table_header(d: *tr.Doc, parent: i32) -> i32 {
    let pn = ix(parent)
    if d.nodes[pn].table_visited { ret parent }
    let line = inp(d)
    if ct.scan_table_start(line, ix(d.first_nonspace)) == 0usize { ret parent }
    let (dok, delim_row) = row_from_string(d, line[ix(d.first_nonspace)..line.len])
    if !dok { ret parent }
    let parent_string = tr.content(d, parent)
    let (hok, header_row) = row_from_string(d, parent_string)
    if !hok || header_row.n != delim_row.n {
        d.nodes[pn].table_visited = true
        ret parent
    }
    d.nodes[pn].kind = tr.K_TABLE
    if header_row.paragraph_offset > 0i32 {
        let para = tr.new_node(d, tr.K_PARAGRAPH)
        let ptxt = ci.trim_str(unescape_pipes(d, parent_string[0usize..ix(header_row.paragraph_offset)]))
        tr.content_set(d, para, ptxt)
        tr.insert_before(d, parent, para)
    }
    d.nodes[pn].ncols = i32(header_row.n)
    var al = ct.buf_new(d.a, delim_row.n + 1usize)
    var i = 0usize
    while i < delim_row.n {
        let cb = delim_row.cells[i].buf
        let left = cb.len > 0usize && cb[0usize] == 58u8
        let right = cb.len > 0usize && cb[cb.len - 1usize] == 58u8
        if left && right { ct.putc(&al, 99u8) } else {
        if left { ct.putc(&al, 108u8) } else {
        if right { ct.putc(&al, 114u8) } else { ct.putc(&al, 0u8) }
        }
        }
        i += 1usize
    }
    d.nodes[pn].aligns = ct.view(&al)
    let hdr = add_child(d, parent, tr.K_ROW, d.nodes[pn].sc)
    d.nodes[ix(hdr)].el = d.nodes[pn].sl
    d.nodes[ix(hdr)].sl = d.nodes[pn].sl
    d.nodes[ix(hdr)].ec = d.nodes[pn].sc + i32(parent_string.len) - 2i32
    d.nodes[ix(hdr)].is_header = true
    i = 0usize
    while i < header_row.n {
        let cell = header_row.cells[i]
        let hc = add_child(d, hdr, tr.K_CELL, d.nodes[pn].sc + cell.start_offset)
        d.nodes[ix(hc)].sl = d.nodes[pn].sl
        d.nodes[ix(hc)].el = d.nodes[pn].sl
        d.nodes[ix(hc)].internal_off = cell.internal_offset
        d.nodes[ix(hc)].ec = d.nodes[pn].sc + cell.end_offset
        set_cell_content(d, hc, cell.buf)
        d.nodes[ix(hc)].cell_index = i32(i)
        i += 1usize
    }
    d.nodes[pn].nrows += 1i32
    d.nodes[pn].nonempty += i32(i)
    advance_offset(d, i32(d.line.len) - 1i32 - d.offset, false)
    ret parent
}

fn try_opening_table_row(d: *tr.Doc, parent: i32) -> i32 {
    if d.blank { ret tr.NIL }
    let pn = ix(parent)
    let rb = add_child(d, parent, tr.K_ROW, d.nodes[pn].sc)
    d.nodes[ix(rb)].ec = d.nodes[pn].ec
    let line = inp(d)
    let (rok, row) = row_from_string(d, line[ix(d.first_nonspace)..line.len])
    if !rok {
        tr.unlink(d, rb)
        ret tr.NIL
    }
    let table_columns = d.nodes[pn].ncols
    var i = 0i32
    while i < i32(row.n) && i < table_columns {
        let cell = row.cells[ix(i)]
        let node = add_child(d, rb, tr.K_CELL, d.nodes[pn].sc + cell.start_offset)
        d.nodes[ix(node)].internal_off = cell.internal_offset
        d.nodes[ix(node)].ec = d.nodes[pn].sc + cell.end_offset
        set_cell_content(d, node, cell.buf)
        d.nodes[ix(node)].cell_index = i
        i += 1i32
    }
    d.nodes[pn].nrows += 1i32
    d.nodes[pn].nonempty += i
    while i < table_columns {
        let node = add_child(d, rb, tr.K_CELL, 0i32)
        d.nodes[ix(node)].cell_index = i
        i += 1i32
    }
    advance_offset(d, i32(d.line.len) - 1i32 - d.offset, false)
    ret rb
}

fn table_matches(d: *tr.Doc, container: i32) -> bool {
    if d.nodes[ix(container)].kind != tr.K_TABLE { ret false }
    let line = inp(d)
    let (ok_row, row) = row_from_string(d, line[ix(d.first_nonspace)..line.len])
    ret ok_row && row.n > 0usize
}

// --- The line loop.

fn parse_block_quote_prefix(d: *tr.Doc) -> bool {
    var matched = false
    if d.indent <= 3i32 && lc(d, d.first_nonspace) == 62u8 { matched = true }
    if matched {
        advance_offset(d, d.indent + 1i32, true)
        if ct.is_blank_char(lc(d, d.offset)) { advance_offset(d, 1i32, true) }
        ret true
    }
    ret false
}

fn parse_item_prefix(d: *tr.Doc, container: i32) -> bool {
    let n = ix(container)
    if d.indent >= d.nodes[n].marker_off + d.nodes[n].padding {
        advance_offset(d, d.nodes[n].marker_off + d.nodes[n].padding, true)
        ret true
    }
    if d.blank && d.nodes[n].first != tr.NIL {
        advance_offset(d, d.first_nonspace - d.offset, false)
        ret true
    }
    ret false
}

// Returns (matches, should_continue).
fn parse_code_block_prefix(d: *tr.Doc, container: i32) -> (bool, bool) {
    let n = ix(container)
    if !d.nodes[n].fenced {
        if d.indent >= 4i32 {
            advance_offset(d, 4i32, true)
            ret (true, true)
        }
        if d.blank {
            advance_offset(d, d.first_nonspace - d.offset, false)
            ret (true, true)
        }
        ret (false, true)
    }
    var matched = 0i32
    if d.indent <= 3i32 && lc(d, d.first_nonspace) == d.nodes[n].fence_char {
        matched = i32(ct.scan_close_code_fence(inp(d), ix(d.first_nonspace)))
    }
    if matched >= d.nodes[n].fence_len && matched > 0i32 {
        advance_offset(d, matched, false)
        d.current = finalize(d, container)
        ret (false, false)
    }
    var i = d.nodes[n].fence_off
    while i > 0i32 && ct.is_blank_char(lc(d, d.offset)) {
        advance_offset(d, 1i32, true)
        i -= 1i32
    }
    ret (true, true)
}

fn parse_html_block_prefix(d: *const tr.Doc, container: i32) -> bool {
    let t = d.nodes[ix(container)].html_type
    if t >= 1i32 && t <= 5i32 { ret true }
    ret !d.blank
}

// For each open container, does this line continue it? Answers the last container that matched
// (NIL when a closing fence ended the line) and whether all of them did.
fn check_open_blocks(d: *tr.Doc) -> (i32, bool) {
    var should_continue = true
    var container = d.root
    var all_matched = false
    var done = false
    while !done && last_child_is_open(d, container) {
        container = d.nodes[ix(container)].last
        let kind = d.nodes[ix(container)].kind
        find_first_nonspace(d)
        if kind == tr.K_TABLE {
            if !table_matches(d, container) { done = true }
            continue
        }
        if kind == tr.K_ROW || kind == tr.K_CELL {
            done = true
            continue
        }
        if kind == tr.K_BLOCK_QUOTE {
            if !parse_block_quote_prefix(d) { done = true }
        } else {
            if kind == tr.K_ITEM {
                if !parse_item_prefix(d, container) { done = true }
            } else {
                if kind == tr.K_CODE_BLOCK {
                    let (m, sc) = parse_code_block_prefix(d, container)
                    should_continue = sc
                    if !m { done = true }
                } else {
                    if kind == tr.K_HEADING {
                        done = true
                    } else {
                        if kind == tr.K_HTML_BLOCK {
                            if !parse_html_block_prefix(d, container) { done = true }
                        } else {
                            if kind == tr.K_PARAGRAPH {
                                if d.blank { done = true }
                            }
                        }
                    }
                }
            }
        }
    }
    if !done { all_matched = true }
    if !all_matched { container = d.nodes[ix(container)].parent }
    if !should_continue { container = tr.NIL }
    ret (container, all_matched)
}

fn tasklist_checked(line: str) -> bool {
    var i = 0usize
    while i + 2usize < line.len {
        if line[i] == 91u8 && (line[i + 1usize] == 120u8 || line[i + 1usize] == 88u8) && line[i + 2usize] == 93u8 { ret true }
        i += 1usize
    }
    ret false
}

fn open_new_blocks(d: *tr.Doc, container_in: i32, all_matched: bool) -> i32 {
    var container = container_in
    var maybe_lazy = d.nodes[ix(d.current)].kind == tr.K_PARAGRAPH
    var cont_type = d.nodes[ix(container)].kind
    var depth = 0i32
    while cont_type != tr.K_CODE_BLOCK && cont_type != tr.K_HTML_BLOCK {
        depth += 1i32
        find_first_nonspace(d)
        let indented = d.indent >= 4i32
        var matched = 0i32
        var handled = false
        if !indented && lc(d, d.first_nonspace) == 62u8 {
            let bqstart = d.first_nonspace
            advance_offset(d, d.first_nonspace + 1i32 - d.offset, false)
            if ct.is_blank_char(lc(d, d.offset)) { advance_offset(d, 1i32, true) }
            container = add_child(d, container, tr.K_BLOCK_QUOTE, bqstart + 1i32)
            handled = true
        }
        if !handled && !indented {
            matched = i32(ct.scan_atx_heading_start(inp(d), ix(d.first_nonspace)))
            if matched > 0i32 {
                let hstart = d.first_nonspace
                advance_offset(d, d.first_nonspace + matched - d.offset, false)
                container = add_child(d, container, tr.K_HEADING, hstart + 1i32)
                var hashpos = d.first_nonspace
                var level = 0i32
                while lc(d, hashpos) == 35u8 {
                    level += 1i32
                    hashpos += 1i32
                }
                d.nodes[ix(container)].level = level
                d.nodes[ix(container)].setext = false
                d.nodes[ix(container)].internal_off = matched
                handled = true
            }
        }
        if !handled && !indented {
            matched = i32(ct.scan_open_code_fence(inp(d), ix(d.first_nonspace)))
            if matched > 0i32 {
                container = add_child(d, container, tr.K_CODE_BLOCK, d.first_nonspace + 1i32)
                let c = ix(container)
                d.nodes[c].fenced = true
                d.nodes[c].fence_char = lc(d, d.first_nonspace)
                if matched > 255i32 { d.nodes[c].fence_len = 255i32 } else { d.nodes[c].fence_len = matched }
                d.nodes[c].fence_off = d.first_nonspace - d.offset
                d.nodes[c].info = ""
                advance_offset(d, d.first_nonspace + matched - d.offset, false)
                handled = true
            }
        }
        if !handled && !indented {
            matched = i32(ct.scan_html_block_start(inp(d), ix(d.first_nonspace)))
            if matched == 0i32 && cont_type != tr.K_PARAGRAPH {
                matched = i32(ct.scan_html_block_start_7(inp(d), ix(d.first_nonspace)))
            }
            if matched > 0i32 {
                container = add_child(d, container, tr.K_HTML_BLOCK, d.first_nonspace + 1i32)
                d.nodes[ix(container)].html_type = matched
                handled = true
            }
        }
        if !handled && !indented && cont_type == tr.K_PARAGRAPH {
            let lev = i32(ct.scan_setext_heading_line(inp(d), ix(d.first_nonspace)))
            if lev > 0i32 {
                let has = resolve_references(d, container)
                if has {
                    d.nodes[ix(container)].kind = tr.K_HEADING
                    d.nodes[ix(container)].level = lev
                    d.nodes[ix(container)].setext = true
                    advance_offset(d, i32(d.llen) - 1i32 - d.offset, false)
                }
                handled = true
            }
        }
        if !handled && !indented && !(cont_type == tr.K_PARAGRAPH && !all_matched) && d.thematic_kill <= d.first_nonspace {
            matched = scan_thematic_break(d, d.first_nonspace)
            if matched > 0i32 {
                container = add_child(d, container, tr.K_THEMATIC, d.first_nonspace + 1i32)
                advance_offset(d, i32(d.llen) - 1i32 - d.offset, false)
                handled = true
            }
        }
        if !handled && (!indented || cont_type == tr.K_LIST) && d.indent < 4i32 && depth < 100i32 {
            let (m, ld) = parse_list_marker(d, d.first_nonspace, d.nodes[ix(container)].kind == tr.K_PARAGRAPH)
            if m > 0i32 {
                var padding = 0i32
                advance_offset(d, d.first_nonspace + m - d.offset, false)
                let save_partial = d.partial_tab
                let save_offset = d.offset
                let save_column = d.column
                while d.column - save_column <= 5i32 && ct.is_blank_char(lc(d, d.offset)) { advance_offset(d, 1i32, true) }
                let i = d.column - save_column
                if i >= 5i32 || i < 1i32 || ct.is_line_end(lc(d, d.offset)) {
                    padding = m + 1i32
                    d.offset = save_offset
                    d.column = save_column
                    d.partial_tab = save_partial
                    if i > 0i32 { advance_offset(d, 1i32, true) }
                } else {
                    padding = m + i
                }
                let marker_offset = d.indent
                if cont_type != tr.K_LIST || !lists_match(d, container, &ld) {
                    container = add_child(d, container, tr.K_LIST, d.first_nonspace + 1i32)
                    let l = ix(container)
                    d.nodes[l].list_type = ld.list_type
                    d.nodes[l].bullet = ld.bullet
                    d.nodes[l].delim = ld.delim
                    d.nodes[l].start = ld.start
                    d.nodes[l].marker_off = marker_offset
                    d.nodes[l].padding = padding
                }
                container = add_child(d, container, tr.K_ITEM, d.first_nonspace + 1i32)
                let it = ix(container)
                d.nodes[it].list_type = ld.list_type
                d.nodes[it].bullet = ld.bullet
                d.nodes[it].delim = ld.delim
                d.nodes[it].start = ld.start
                d.nodes[it].marker_off = marker_offset
                d.nodes[it].padding = padding
                handled = true
            }
        }
        if !handled && indented && !maybe_lazy && !d.blank {
            advance_offset(d, 4i32, true)
            container = add_child(d, container, tr.K_CODE_BLOCK, d.offset + 1i32)
            let c = ix(container)
            d.nodes[c].fenced = false
            d.nodes[c].fence_char = 0u8
            d.nodes[c].fence_len = 0i32
            d.nodes[c].fence_off = 0i32
            d.nodes[c].info = ""
            handled = true
        }
        if !handled {
            // The extensions get a say: tables, task lists.
            var new_container = tr.NIL
            if d.x_table && !indented {
                let ck = d.nodes[ix(container)].kind
                if ck == tr.K_PARAGRAPH {
                    new_container = try_opening_table_header(d, container)
                } else {
                    if ck == tr.K_TABLE { new_container = try_opening_table_row(d, container) }
                }
            }
            if new_container == tr.NIL && d.x_tasklist && d.nodes[ix(container)].kind == tr.K_ITEM {
                let line = inp(d)
                if ct.scan_tasklist(line) > 0usize {
                    d.nodes[ix(container)].tasklist = true
                    advance_offset(d, 3i32, false)
                    d.nodes[ix(container)].checked = tasklist_checked(line)
                }
            }
            if new_container == tr.NIL { break }
            container = new_container
        }
        if accepts_lines(d.nodes[ix(container)].kind) { break }
        cont_type = d.nodes[ix(container)].kind
        maybe_lazy = false
    }
    ret container
}

fn chop_trailing_hashtags(d: *tr.Doc) {
    var n = d.llen
    while n > 0usize && ct.is_space(ct.pk(d.line, n - 1usize)) { n -= 1usize }
    d.llen = n
    var k = i32(n) - 1i32
    let orig = k
    while k >= 0i32 && lc(d, k) == 35u8 { k -= 1i32 }
    if k != orig && k >= 0i32 && ct.is_blank_char(lc(d, k)) {
        n = ix(k)
        while n > 0usize && ct.is_space(ct.pk(d.line, n - 1usize)) { n -= 1usize }
        d.llen = n
    }
}

fn add_text_to_container(d: *tr.Doc, container_in: i32, last_matched: i32) {
    var container = container_in
    find_first_nonspace(d)
    let cn = ix(container)
    if d.blank && d.nodes[cn].last != tr.NIL { d.nodes[ix(d.nodes[cn].last)].last_blank = true }
    let ctype = d.nodes[cn].kind
    let last_line_blank = d.blank && ctype != tr.K_BLOCK_QUOTE && ctype != tr.K_HEADING && ctype != tr.K_THEMATIC && !(ctype == tr.K_CODE_BLOCK && d.nodes[cn].fenced) && !(ctype == tr.K_ITEM && d.nodes[cn].first == tr.NIL && d.nodes[cn].sl == d.line_number)
    d.nodes[cn].last_blank = last_line_blank
    var tmp = container
    while d.nodes[ix(tmp)].parent != tr.NIL {
        let p = d.nodes[ix(tmp)].parent
        d.nodes[ix(p)].last_blank = false
        tmp = p
    }
    if d.current != last_matched && container == last_matched && !d.blank && d.nodes[ix(d.current)].kind == tr.K_PARAGRAPH {
        add_line(d, d.current)
        ret
    }
    while d.current != last_matched { d.current = finalize(d, d.current) }
    let kind = d.nodes[ix(container)].kind
    if kind == tr.K_CODE_BLOCK {
        add_line(d, container)
    } else {
        if kind == tr.K_HTML_BLOCK {
            add_line(d, container)
            var ends = false
            let t = d.nodes[ix(container)].html_type
            if t >= 1i32 && t <= 5i32 { ends = ct.scan_html_block_end(usize(t), inp(d), ix(d.first_nonspace)) }
            if ends { container = finalize(d, container) }
        } else {
            if d.blank {
                // nothing to add
            } else {
                if accepts_lines(kind) {
                    if kind == tr.K_HEADING && !d.nodes[ix(container)].setext { chop_trailing_hashtags(d) }
                    advance_offset(d, d.first_nonspace - d.offset, false)
                    add_line(d, container)
                } else {
                    container = add_child(d, container, tr.K_PARAGRAPH, d.first_nonspace + 1i32)
                    advance_offset(d, d.first_nonspace - d.offset, false)
                    add_line(d, container)
                }
            }
        }
    }
    d.current = container
}

fn process_line(d: *tr.Doc, line: str) {
    // `line` already ends with a newline.
    d.line = line
    d.llen = line.len
    d.offset = 0i32
    d.column = 0i32
    d.first_nonspace = 0i32
    d.first_nonspace_col = 0i32
    d.thematic_kill = 0i32
    d.indent = 0i32
    d.blank = false
    d.partial_tab = false
    if d.line_number == 0i32 && line.len >= 3usize && line[0usize] == 239u8 && line[1usize] == 187u8 && line[2usize] == 191u8 { d.offset += 3i32 }
    d.line_number += 1i32
    let (last_matched, all_matched) = check_open_blocks(d)
    if last_matched != tr.NIL {
        let current = d.current
        let container = open_new_blocks(d, last_matched, all_matched)
        if current == d.current { add_text_to_container(d, container, last_matched) }
    }
    d.last_line_len = i32(d.llen)
    if d.last_line_len > 0i32 && lc(d, d.last_line_len - 1i32) == 10u8 { d.last_line_len -= 1i32 }
    if d.last_line_len > 0i32 && lc(d, d.last_line_len - 1i32) == 13u8 { d.last_line_len -= 1i32 }
    d.line = ""
    d.llen = 0usize
}

// Feeds a line (without its terminator) to the parser.
fn feed_line(d: *tr.Doc, text: str, start: usize, end: usize) {
    var b = ct.buf_new(d.a, end - start + 8usize)
    var i = start
    while i < end {
        if text[i] == 0u8 {
            ct.put(&b, "\xef\xbf\xbd")
        } else {
            ct.putc(&b, text[i])
        }
        i += 1usize
    }
    ct.putc(&b, 10u8)
    if b.failed {
        d.failed = true
        ret
    }
    process_line(d, ct.view(&b))
}

fn finalize_document(d: *tr.Doc) {
    while d.current != d.root { d.current = finalize(d, d.current) }
    let _ = finalize(d, d.root)
    var it = tr.iter_new(d.root)
    while tr.iter_next(d, &it) {
        if it.enter && contains_inlines(d.nodes[ix(it.node)].kind) { ci.parse_inlines(d, it.node) }
    }
}

// Parses the whole text; the tree is in `d` from `d.root` down.
fn parse(d: *tr.Doc, text: str) {
    d.root = tr.new_node(d, tr.K_DOCUMENT)
    d.nodes[ix(d.root)].open = true
    d.nodes[ix(d.root)].sl = 1i32
    d.nodes[ix(d.root)].sc = 1i32
    d.nodes[ix(d.root)].el = 1i32
    d.current = d.root
    var at = 0usize
    while at < text.len {
        var eol = at
        while eol < text.len && text[eol] != 10u8 && text[eol] != 13u8 { eol += 1usize }
        feed_line(d, text, at, eol)
        at = eol
        if at < text.len {
            if text[at] == 13u8 { at += 1usize }
            if at < text.len && text[at] == 10u8 { at += 1usize }
        }
    }
    finalize_document(d)
    tr.consolidate_text(d, d.root)
    if d.x_autolink { ci.autolink_postprocess(d) }
}
