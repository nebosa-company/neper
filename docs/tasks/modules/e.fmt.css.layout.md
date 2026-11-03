# e.fmt.css.layout — 1 of 284 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/css/layout.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/css/layout.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.css.style` | source | `lib/e/fmt/css/style.e` | 6 |
| `e.fmt.dom` | source | `lib/e/fmt/dom.e` | 6 |
| `e.fmt.html` | partial | `lib/e/fmt/html.e` | 6 |
| `e.gfx.cssvalue` | source | `lib/e/gfx/cssvalue.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.segment` | source | `lib/e/text/segment.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type FontMetrics = struct { ascent: f64, descent: f64, line_gap: f64, x_height: f64 }
type Intrinsic = struct { kind: u8, has_width: bool, width: f64, has_height: bool, height: f64, ratio: f64 }
type Measure = struct { ctx: *void, width: fn(*void, *const style.Style, str) -> f64, metrics: fn(*void, *const style.Style) -> FontMetrics, intrinsic: fn(*void, html.NodeId, *const style.Style) -> Intrinsic }
type Inner = enum u8 { Flow, FlowRoot, Flex, Grid, Table, Replaced, Text, Break, Marker, RowGroup, Row, Cell, Caption, ColumnGroup, Column }
const NONE: u32 = 4294967295u32
type Box = struct { inner: Inner, inline_level: bool, anonymous: bool, positioned_out: bool, node: u32, style: u32, parent: u32, first: u32, last: u32, prev: u32, next: u32, x: f64, y: f64, w: f64, h: f64, margin: [4]f64, border: [4]f64, padding: [4]f64, text: str, line_first: u32, line_count: u32, baseline: f64, has_baseline: bool, overflow_w: f64, overflow_h: f64, aux: u32, aux2: u32, min_c: f64, max_c: f64, has_c: bool, in_layout: bool, proc: str, coll: bool, cbd: [4]f64 }
type FragKind = enum u8 { Text, Segment, Atomic, Marker }
type Frag = struct { kind: FragKind, box: u32, x: f64, y: f64, w: f64, h: f64, text: str, first: bool, last: bool }
type Line = struct { x: f64, y: f64, w: f64, h: f64, baseline: f64, frag_first: u32, frag_count: u32, overflow_ellipsis: bool }
type Layout = struct { a: *mem.Arena, d: *const dom.Dom, styles: []const style.Style, measure: Measure, boxes: list.List[Box], lines: list.List[Line], frags: list.List[Frag], anon: list.List[style.Style], root: u32, viewport_width: f64, viewport_height: f64, doc_width: f64, doc_height: f64, floats: list.List[FloatRec], tables: list.List[TableData], counters: list.List[CounterInst], quote_depth: i64, gen_depth: usize, orth_fb: f64, vmode: u8, tr1: []style.Style, tr2: []style.Style, grids: list.List[GridGeom], rules: list.List[ColRule] }
type FloatRec = struct { box: u32, x: f64, y: f64, w: f64, h: f64, left: bool, root: u32 }
fn st(l: *const Layout, id: u32) -> *const style.Style
fn bx(l: *Layout, id: u32) -> *Box
fn bstyle(l: *const Layout, id: u32) -> *const style.Style
fn new_box(l: *Layout, inner: Inner, inline_level: bool, anonymous: bool, node: u32, style_id: u32) -> u32
fn append(l: *Layout, parent: u32, child: u32)
fn detach(l: *Layout, child: u32)
fn anon_style(l: *Layout, parent_style: u32, display: style.Display) -> u32
fn is_punct(c: u32) -> bool
fn is_combining(c: u32) -> bool
fn find_first_text(l: *Layout, b: u32) -> u32
fn apply_first_letter(l: *Layout, b: u32, ps: *const style.Style)
type CounterInst = struct { name: str, value: i64, depth: usize }
fn find_counter(l: *const Layout, name: str) -> i64
fn counter_instantiate(l: *Layout, name: str, value: i64)
fn apply_counter_props(l: *Layout, s: *const style.Style)
fn counter_pairs(l: *Layout, text: str, op: u8, default_value: i64)
fn format_counter(l: *Layout, value: i64, kind: str) -> str
fn join_parts(a: *mem.Arena, parts: []const str) -> str
fn quote_pair(l: *Layout, s: *const style.Style, depth: i64, close: bool) -> str
fn eval_content(l: *Layout, s: *const style.Style, node: u32) -> (str, bool)
fn push_style(l: *Layout, s: *const style.Style) -> u32
fn inner_for_display(d: style.Display) -> Inner
fn gen_pseudo(l: *Layout, node: u32, parent_box: u32, kind: usize)
fn is_replaced_tag(name: str) -> bool
fn name_in(set: str, name: str) -> bool
fn is_block_level(d: style.Display) -> bool
fn is_inline_level_display(d: style.Display) -> bool
fn is_out_of_flow(s: *const style.Style) -> bool
fn gen_children(l: *Layout, node: u32, parent_box: u32)
fn gen_node(l: *Layout, node: u32, parent_box: u32, parent_node: u32)
fn list_ordinal(l: *Layout, node: u32) -> i64
fn has_start_attr(l: *Layout, parent: u32) -> bool
fn is_ws_only(s: str) -> bool
fn is_block_container(l: *const Layout, b: u32) -> bool
fn fix_anonymous(l: *Layout, b: u32)
fn promote_inline_with_blocks(l: *Layout, b: u32)
fn flush_run(l: *Layout, parent: u32, first: u32, last: u32)
fn collapses(l: *const Layout, b: u32) -> bool
fn wrap_flex_items(l: *Layout, b: u32)
type Flag = struct { v: bool, cleared: bool }
fn resolve_len(len: style.Len, basis: f64) -> (f64, bool)
fn resolve_or(len: style.Len, basis: f64, fallback: f64) -> f64
fn maxf(x: f64, y: f64) -> f64
fn minf(x: f64, y: f64) -> f64
type Margin = struct { pos: f64, neg: f64 }
fn margin_of(v: f64) -> Margin
fn collapse(x: Margin, y: Margin) -> Margin
fn margin_value(m: Margin) -> f64
fn no_margin() -> Margin
fn is_bfc_root(l: *const Layout, b: u32) -> bool
fn border_px(s: *const style.Style, side: usize) -> f64
fn resolve_edges(l: *Layout, b: u32, cbw: f64)
fn resolve_margins_fixed(l: *Layout, b: u32, cbw: f64)
fn is_auto(len: style.Len) -> bool
fn horizontal_extras(bb: *const Box) -> f64
fn vertical_extras(bb: *const Box) -> f64
fn to_content_w(l: *const Layout, b: u32, outer: f64) -> f64
fn to_content_h(l: *const Layout, b: u32, outer: f64) -> f64
fn clamp_width(l: *const Layout, b: u32, w: f64, cbw: f64) -> f64
fn clamp_height(l: *const Layout, b: u32, h: f64, cbh: f64) -> f64
fn float_edge_left(l: *const Layout, base: usize, y0: f64, y1: f64, floor_x: f64) -> f64
fn float_edge_right(l: *const Layout, base: usize, y0: f64, y1: f64, ceil_x: f64) -> f64
fn float_bottom(l: *const Layout, base: usize, side: u32, floor: f64) -> f64
fn next_float_end(l: *const Layout, base: usize, y: f64) -> f64
fn float_top_floor(l: *const Layout, base: usize, floor: f64) -> f64
type PieceKind = enum u8 { Text, Space, Hard, Atomic, Open, Close, Float, Abs, Marker }
type Piece = struct { kind: PieceKind, box: u32, text: str, w: f64, trail: f64, soft: bool, ink: bool, start: usize, clen: usize }
type Builder = struct { l: *Layout, pieces: list.List[Piece], last_space: bool, ws_pending: bool, cbw: f64, cbh: f64 }
fn push_piece(bd: *Builder, p: Piece)
fn is_space_byte(c: u8) -> bool
fn spacing_extra(s: *const style.Style, text: str) -> f64
fn text_advance(l: *const Layout, s: *const style.Style, text: str) -> f64
fn apply_transform(l: *const Layout, s: *const style.Style, text: str) -> str
fn process_text(l: *const Layout, b: u32, ends_space: *Flag) -> str
fn font_ad(l: *const Layout, s: *const style.Style) -> (f64, f64)
type Flow = struct { base: usize, ox: f64, oy: f64 }
fn emit_text_pieces(bd: *Builder, b: u32, ends_space: *Flag)
fn collect_inline(bd: *Builder, b: u32, ends_space: *Flag)
fn alpha_text(l: *const Layout, n: i64, upper: bool) -> str
fn roman_text(l: *const Layout, n: i64, upper: bool) -> str
fn number_text(l: *const Layout, n: i64, pad: usize) -> str
type TextBuf = struct { b: str.Builder, bad: bool }
fn new_text(a: *mem.Arena, cap: usize) -> TextBuf
fn text_put(t: *TextBuf, s: str)
fn text_put_byte(t: *TextBuf, c: u8)
fn text_take(t: *TextBuf) -> str
fn marker_string(l: *const Layout, b: u32) -> str
type Open = struct { box: u32, shift: f64, start: f64 }
fn valign_shift(l: *const Layout, s: *const style.Style, ps: *const style.Style, a: f64, d: f64, lh: f64) -> f64
fn line_align_x(s: *const style.Style, base: style.TextAlign, last_line: bool, explicit_justify: bool, avail: f64, width: f64, left: f64) -> f64
fn place_float(l: *Layout, fc: *Flow, f: u32, cbx: f64, cbw: f64, y_min: f64, parent: u32)
type Ifc = struct { l: *Layout, bd: Builder, cont: u32, cs: *const style.Style, cbw: f64, fc: *Flow, y: f64, first_line: bool, open: [64]u32, open_count: usize, sa: f64, sd: f64, own: list.List[u32] }
type Scan = struct { restart: bool, end: usize, lead: usize, forced: bool, line_x: f64, avail: f64 }
fn split_piece(x: *Ifc, j: usize, max_w: f64) -> bool
fn scan_line(x: *Ifc, i: usize) -> Scan
fn flush_text_frag(l: *Layout, bxid: u32, x: f64, text: str, w: f64, shift: f64, baseline: f64)
fn emit_segment(l: *Layout, ob: u32, x0: f64, x1: f64, baseline: f64, shift: f64, first: bool, last: bool)
fn layout_inline_content(l: *Layout, cont: u32, cbw: f64, cbh: f64, fc: *Flow) -> f64
fn emit_line(x: *Ifc, scan: Scan, end: usize) -> f64
fn replaced_intrinsic(l: *Layout, b: u32) -> Intrinsic
fn default_replaced(i: Intrinsic) -> (f64, f64)
fn outer_content_widths(l: *Layout, c: u32) -> (f64, f64)
fn content_widths(l: *Layout, b: u32) -> (f64, f64)
fn has_inline_content(l: *const Layout, b: u32) -> bool
fn inline_widths(l: *Layout, cont: u32) -> (f64, f64)
fn if_trail(p: Piece) -> f64
fn collect_inline_intrinsic(bd: *Builder, b: u32, ends_space: *Flag)
fn used_replaced_size(l: *Layout, b: u32, cbw: f64, cbh: f64) -> (f64, f64)
fn auto_margin_h(s: *const style.Style, side: usize) -> bool
fn used_width_block(l: *Layout, c: u32, cbw: f64, avail: f64)
fn used_margins_vertical(l: *Layout, c: u32, cbw: f64)
fn in_flow_block(l: *const Layout, c: u32) -> bool
fn self_collapsing(l: *Layout, c: u32, cbw: f64) -> bool
fn peek_top(l: *Layout, c: u32, cbw: f64, floats: bool) -> Margin
fn last_baseline(l: *const Layout, b: u32) -> (bool, f64)
fn first_baseline(l: *const Layout, b: u32) -> (bool, f64)
fn layout_in_new_bfc(l: *Layout, b: u32, cw: f64, ch: f64) -> f64
fn set_baseline(l: *Layout, b: u32)
fn layout_atomic(l: *Layout, b: u32, cbw: f64, cbh: f64)
fn layout_contents_height(l: *Layout, b: u32, cw: f64, cbh: f64)
fn layout_children(l: *Layout, b: u32, cw: f64, ch: f64, fc: *Flow, through_top: bool) -> (f64, Margin)
fn position_markers(l: *Layout, b: u32)
fn layout_block_child(l: *Layout, p: u32, c: u32, cw: f64, ch: f64, fc: *Flow, y_in: f64, acc: *Margin, consumed: *Flag, ox0: f64, oy0: f64) -> f64
fn size_block_box(l: *Layout, c: u32, cbw: f64, offer: f64)
fn apply_relative(l: *Layout, c: u32, cbw: f64, cbh: f64)
fn block_widths(l: *Layout, b: u32) -> (f64, f64)
type CellInfo = struct { box: u32, row: usize, col: usize, rs: usize, cs: usize, min: f64, max: f64, spec: f64, pct: f64 }
type TableData = struct { cols: usize, rows: usize, cells: list.List[CellInfo], col_min: []f64, col_max: []f64, col_w: []f64, col_pct: []f64, col_spec: []f64, row_h: []f64, row_y: []f64, row_box: []u32, row_above: []f64, row_below: []f64, sh: f64, sv: f64, sum_min: f64, sum_max: f64, collapsed: bool, hedge: []Edge, vedge: []Edge, cap_t: f64, cap_b: f64 }
fn is_ws_text(l: *const Layout, k: u32) -> bool
fn wrap_table_run(l: *Layout, parent: u32, first: u32, last: u32, inner: Inner, display: style.Display)
fn fix_table_like(l: *Layout, b: u32)
fn span_attr(l: *const Layout, node: u32, name: str) -> usize
fn row_order(l: *const Layout, table: u32, out: *list.List[u32])
fn is_pct_width(len: style.Len) -> bool
fn build_table(l: *Layout, t: u32) -> u32
fn table_widths(l: *Layout, t: u32) -> (f64, f64)
fn table_min_width(l: *Layout, t: u32) -> f64
fn distribute_columns(l: *Layout, ti: u32, tw: f64, fixed_layout: bool)
fn is_baseline_valign(v: style.VAlign) -> bool
fn layout_table(l: *Layout, t: u32, cw: f64, ch: f64) -> f64
type FlexItem = struct { box: u32, order: i64, grow: f64, shrink: f64, basis: f64, hyp: f64, target: f64, min_main: f64, max_main: f64, frozen: bool, ms: f64, me: f64, cs: f64, ce: f64, ams: bool, ame: bool, acs: bool, ace: bool, main_ex: f64, cross_ex: f64, cross: f64, up: f64, align: style.Align, pos_main: f64, pos_cross: f64 }
fn flex_is_row(s: *const style.Style) -> bool
fn flex_gap(len: style.Len, basis: f64) -> f64
fn flex_item_align(cs: *const style.Style, is: *const style.Style) -> style.Align
fn flex_in(l: *const Layout, kid: u32) -> bool
fn flex_widths(l: *Layout, b: u32) -> (f64, f64)
fn flex_cross_width(l: *Layout, id: u32, cw: f64, stretch: bool) -> f64
fn flex_place_item(l: *Layout, id: u32, w: f64, hspec: f64)
fn layout_flex(l: *Layout, b: u32, cw: f64, ch: f64) -> f64
fn if_factor(grow_mode: bool, grow: f64, shrink: f64) -> f64
fn inf() -> f64
type SizeFn = struct { kind: u8, v: f64 }
type GTrack = struct { min: SizeFn, max: SizeFn, base: f64, limit: f64, pos: f64, collapsed: bool, fit: bool }
type GName = struct { name: str, line: i32 }
type GArea = struct { name: str, r0: i32, r1: i32, c0: i32, c1: i32 }
type LineSpec = struct { kind: u8, n: i32, name: str, span_name: bool }
type GItem = struct { box: u32, order: i64, rs: i32, rn: i32, cs: i32, cn: i32, cmin: f64, cmax: f64, rmin: f64, rmax: f64 }
type GridParse = struct { c: style.Context, em: f64, avail: f64, gap: f64, item_min: f64 }
fn extra_text(s: *const style.Style, name: str) -> (str, bool)
fn push_name(names: *list.List[GName], name: str, line: i32)
fn grid_split(a: *mem.Arena, s: str) -> []const str
fn gp_size(gp: *GridParse, tok: str) -> (SizeFn, bool)
fn gp_track(gp: *GridParse, tok: str, out: *list.List[GTrack]) -> bool
fn gp_list(gp: *GridParse, text: str, out: *list.List[GTrack], names: *list.List[GName])
type Dims = struct { rows: i32, cols: i32 }
fn parse_areas(a: *mem.Arena, text: str, areas: *list.List[GArea], dims: *Dims)
fn parse_line_spec(a: *mem.Arena, text: str) -> LineSpec
fn resolve_line(names: *const list.List[GName], explicit: i32, spec: LineSpec, end: bool, a: *mem.Arena) -> i32
fn resolve_axis(names: *const list.List[GName], explicit: i32, s: LineSpec, e: LineSpec, a: *mem.Arena) -> (i32, i32)
fn split_slash(text: str) -> (str, str, bool)
fn item_axis_specs(a: *mem.Arena, s: *const style.Style, col: bool) -> (LineSpec, LineSpec)
type Grid = struct { cols: []GTrack, rows: []GTrack, nc: usize, nr: usize, items: []GItem, n: usize, gap_c: f64, gap_r: f64, cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32 }
fn occ_free(occ: []bool, ncols: usize, rows_cap: usize, r: usize, c: usize, rn: usize, cn: usize) -> bool
fn occ_mark(occ: []bool, ncols: usize, rows_cap: usize, r: usize, c: usize, rn: usize, cn: usize)
fn grid_autoplace(a: *mem.Arena, items: []GItem, n: usize, ec: i32, er: i32, dense: bool) -> bool
fn swap_axes(items: []GItem, n: usize)
fn auto_track_list(gp: *GridParse, s: *const style.Style, prop: str) -> list.List[GTrack]
fn grid_make_track(auto_list: *const list.List[GTrack], index: usize) -> GTrack
fn grid_build(l: *Layout, b: u32, avail_w: f64, avail_h: f64) -> (*Grid, bool)
fn is_intrinsic_min(k: u8) -> bool
fn is_intrinsic_max(k: u8) -> bool
fn size_tracks(tr: []GTrack, n: usize, gap: f64, avail: f64, items: []GItem, nitems: usize, is_col: bool, min_mode: bool, stretch: bool)
fn tracks_total(tr: []GTrack, n: usize, gap: f64) -> f64
fn position_tracks(tr: []GTrack, n: usize, gap: f64, avail: f64, mode: style.Align)
fn grid_area_size(tr: []GTrack, start: i32, span: i32, gap: f64) -> f64
fn grid_item_width(l: *Layout, id: u32, cs: *const style.Style, area_w: f64) -> f64
fn grid_axis_offset(mode: style.Align, free: f64) -> f64
fn grid_widths(l: *Layout, b: u32) -> (f64, f64)
fn layout_grid(l: *Layout, b: u32, cw: f64, ch: f64) -> f64
type Cols = struct { count: usize, width: f64, gap: f64 }
fn has_columns(s: *const style.Style) -> bool
fn columns_for(l: *Layout, s: *const style.Style, cw: f64) -> Cols
fn column_of(y: f64, colh: f64) -> usize
fn unbreakable(l: *const Layout, b: u32) -> bool
fn colify(l: *Layout, b: u32, abs_y: f64, colh: f64, stride: f64, apply: bool) -> usize
fn layout_multicol(l: *Layout, b: u32, cw: f64, ch: f64, cols: Cols, fc: *Flow) -> f64
fn abs_origin(l: *const Layout, b: u32) -> (f64, f64)
fn containing_block_of(l: *const Layout, b: u32, fixed: bool) -> u32
fn layout_abs(l: *Layout, b: u32)
fn positioned_pass(l: *Layout, b: u32)
fn extent_pass(l: *Layout, b: u32, ox: f64, oy: f64)
fn layout_document(a: *mem.Arena, d: *const dom.Dom, styles: []const style.Style, measure: Measure, viewport_width: f64, viewport_height: f64) -> (Layout, err)
error TooBig
type ClampScan = struct { seen: usize, n: usize, tail: bool }
type ColRule = struct { box: u32, x: f64, y: f64, w: f64, h: f64, color: u32 }
type Counter = struct { n: usize }
type Edge = struct { w: f64, bs: style.BorderStyle, color: u32, prio: u8, set: bool }
type GridGeom = struct { box: u32, nc: usize, nr: usize, cpos: []f64, csz: []f64, rpos: []f64, rsz: []f64, cnames: list.List[GName], rnames: list.List[GName], ec: i32, er: i32 }
fn bidi_order_pieces(x: *Ifc, lead: usize, tail: usize) -> bool
fn box_ratio(l: *const Layout, b: u32) -> (f64, bool)
fn build_transposed(l: *Layout)
fn clamp_children(l: *Layout, b: u32, ctr: *Counter) -> f64
fn clamp_height_auto(l: *const Layout, b: u32, h: f64, cbh: f64, auto_h: f64) -> f64
fn clamp_hide(l: *Layout, b: u32)
fn clamp_scan(l: *Layout, b: u32, sc: *ClampScan)
fn clamp_walk(l: *Layout, b: u32, ctr: *Counter) -> f64
fn clear_widths(l: *Layout, b: u32)
fn colify_run(l: *Layout, first: u32, stop: u32, origin: f64, base: f64, colh: f64, stride: f64, apply: bool, shift: f64) -> usize
fn collapse_edges(l: *Layout, t: u32, cells: *const list.List[CellInfo], rows: []const u32, nrows: usize, ncols: usize) -> ([]Edge, []Edge)
fn column_rule_of(l: *Layout, s: *const style.Style) -> (f64, u32, bool)
fn edge_of(l: *const Layout, b: u32, side: usize, prio: u8) -> Edge
fn edge_wins(a: Edge, b: Edge) -> bool
fn fixed_block_size(l: *const Layout, b: u32) -> f64
fn flex_baseline(l: *const Layout, b: u32) -> (bool, f64)
fn frame_side(code: u8, i: usize) -> usize
fn gaps_of(tr: []GTrack, n: usize, gap: f64) -> f64
fn gen_run_in(l: *Layout, rnode: u32, target_box: u32)
fn grid_abs_area(l: *Layout, gb: u32, child: u32, pw: f64, ph: f64, ox: f64, oy: f64) -> (bool, f64, f64, f64, f64)
fn has_box_ratio(l: *const Layout, b: u32) -> bool
fn is_abs_positioned(s: *const style.Style) -> bool
fn is_flow_sibling(l: *const Layout, k: u32) -> bool
fn is_orthogonal(l: *const Layout, b: u32) -> bool
fn is_scroll_container(s: *const style.Style) -> bool
fn is_spanner(l: *const Layout, c: u32) -> bool
fn is_table_part(inner: Inner) -> bool
fn lanes_dense(cs: *const style.Style) -> bool
fn layout_lanes(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64) -> f64
fn layout_lanes_dense(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64) -> f64
fn layout_lanes_rows(l: *Layout, b: u32, g: *Grid, cs: *const style.Style, cw: f64, ch: f64) -> f64
fn layout_multicol_spans(l: *Layout, b: u32, cw: f64, cols: Cols, fc: *Flow) -> f64
fn layout_orthogonal(l: *Layout, c: u32, pbase: f64, pch: f64, fi: f64, fb: f64)
fn line_align_of(l: *Layout, s: *const style.Style, last_line: bool) -> style.TextAlign
fn line_clamp_count(s: *const style.Style) -> usize
fn mode_code(s: *const style.Style) -> u8
fn order_items(l: *Layout, b: u32)
fn orphan_display(l: *const Layout, parent: u32) -> style.Display
fn orthogonal_room(l: *const Layout, c: u32, pch: f64) -> f64
fn overflow_propagated(l: *const Layout, b: u32) -> bool
fn put_edge(arr: []Edge, at: usize, e: Edge)
fn ratio_height(l: *const Layout, b: u32, cw: f64) -> (f64, bool)
fn ratio_width(l: *const Layout, b: u32, ch: f64) -> (f64, bool)
fn record_rules(l: *Layout, b: u32, cols: Cols, used: usize, y: f64, colh: f64)
fn relative_chain(l: *const Layout, b: u32, stop: u32, cbw: f64) -> (f64, f64)
fn relative_offset(s: *const style.Style, cbw: f64, cbh: f64) -> (f64, f64)
fn relative_table_parts(l: *Layout, b: u32, w: f64)
fn remap_children(l: *Layout, p: u32, sw: f64, sh: f64, from: u8, to: u8)
fn remap_edges(from: u8, to: u8, e: [4]f64) -> [4]f64
fn remap_rect(from: u8, to: u8, sw: f64, sh: f64, x: f64, y: f64, w: f64, h: f64) -> (f64, f64, f64, f64)
fn run_in_before(l: *Layout, node: u32) -> u32
fn run_in_target(l: *Layout, node: u32) -> u32
fn shy_hyphen_w(l: *Layout, p: Piece) -> f64
fn static_align_offset(a: style.Align, room: f64, inline_axis: bool) -> f64
fn style_rank(b: style.BorderStyle) -> u8
fn style_value(l: *const Layout, k: usize) -> style.Style
fn subtree_ad(l: *const Layout, o: u32) -> (f64, f64)
fn text_ascent(s: *const style.Style, fm: FontMetrics) -> f64
fn transpose_style(s: style.Style, code: u8) -> style.Style
fn trim_flags(l: *Layout, p: u32) -> u8
fn va_edge_owner(l: *const Layout, b: u32, cont: u32) -> u32
fn visible_tracks(tr: []GTrack, from: usize, to: usize) -> usize
fn wrap_orphan_table_parts(l: *Layout, b: u32)
fn fixed_block_size(l: *const Layout, b: u32) -> f64
fn orthogonal_room(l: *const Layout, c: u32, pch: f64) -> f64
```

## Missing declarations

- [ ] `has_start_attr`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/fmt/css/cascade.e`
- `lib/e/fmt/css/container.e`
- `lib/e/fmt/css/expand.e`†
- `lib/e/fmt/css/geom.e`
- `lib/e/fmt/css/layout.e`‡
- `lib/e/fmt/css/match.e`
- `lib/e/fmt/css/measure.e`
- `lib/e/fmt/css/paint.e`†

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/css/layout.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_css_layout/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
