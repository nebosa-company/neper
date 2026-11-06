/**
 * Which of the registry's chart types the SVG renderer can actually draw.
 *
 * ## Why this is its own file
 *
 * It is data, and it lives apart from the renderer so that a module which only
 * needs to COUNT the types does not have to import one that draws them.
 * `src/language.js` needs the count — the homepage trust bar states it, and a
 * number typed into a sentence rots (it said "8 chart types" against 25 for
 * long enough that a guard test grew up around the wrong figure). But
 * `chart-svg.js` imports `cell-render.js`, which reaches `language.js` again
 * through the field registry and the plugin surface, so importing the renderer
 * there is an import cycle and `tests/import-cycles.test.js` rejects it —
 * correctly, because in a cycle one participant sees a half-initialised
 * namespace and the symptom is a silent `undefined`, not a crash.
 *
 * This file imports nothing. It cannot participate in a cycle, so both the
 * renderer and the translator can read it.
 *
 * ## What it contains
 *
 * `charts/registry.js` enumerates 47 types. `chart-svg.js` draws 22 shapes
 * behind these 25 keys. Its dispatch falls back to a vertical bar for anything
 * it does not know, so offering the full catalogue in a picker would mean
 * choosing "Sankey" and being shown a bar chart with nothing to say it was not
 * a Sankey. This map is what a picker should be built from.
 *
 * ## The two vocabularies disagree about the word "bar"
 *
 * The registry follows the FT Visual Vocabulary, where a BAR runs horizontally
 * and a COLUMN runs vertically. `barChartSVG` in `chart-svg.js` draws VERTICAL
 * bars. So registry `column` is drawn by `barChartSVG` and registry `bar` by
 * `hBarChartSVG` — the opposite of what the names suggest, which is exactly why
 * the mapping is written down here rather than inferred from the id.
 *
 * `stacked-bar` was absent originally: the registry means a horizontal stack
 * and `stackedBarChartSVG` draws a vertical one, so it mapped to
 * `stacked-column` instead. The legacy `'stacked-bar'` string is still accepted
 * by the dispatch for callers that predate this map.
 */
export const RENDERABLE_CHART_TYPES = Object.freeze({
  column: 'bar',
  'ordered-column': 'bar',
  bar: 'hbar',
  'ordered-bar': 'hbar',
  line: 'line',
  area: 'area',
  'stacked-column': 'stacked',
  pie: 'pie',
  donut: 'donut',
  scatter: 'scatter',

  // Tier 1 — see the block above. Each is a transformation of the data or a
  // small variation on a mark already drawn, so none of them needed new
  // geometry. `stacked-bar` finally means what the registry means by it: a
  // HORIZONTAL stack, distinct from the vertical `stacked-column`.
  lollipop: 'lollipop',
  waterfall: 'waterfall',
  funnel: 'funnel',
  histogram: 'histogram',
  slope: 'slope',
  sparkline: 'sparkline',
  'stacked-area': 'stacked-area',
  'stacked-bar': 'hstacked',

  // Tier 2 — new geometry, but self-contained. An arc, a polar polygon and a
  // squarified rectangle are each their own layout; none needs a graph layout,
  // a statistical kernel or geography, which is what keeps them off Tier 3.
  kpi: 'kpi',
  gauge: 'gauge',
  'radial-bar': 'radial-bar',
  radar: 'radar',
  boxplot: 'boxplot',
  treemap: 'treemap',
  heatmap: 'heatmap',
});

/** How many types a user can pick and get the chart they asked for. */
export const RENDERABLE_CHART_TYPE_COUNT = Object.keys(RENDERABLE_CHART_TYPES).length;

/**
 * The DRAWINGS that render every dataset, not only the first.
 *
 * This is §4.2's "a type that is not implemented is not offered" one layer
 * down, and it exists because the page Chart can now be split by a column.
 * `buildChartData` turns a `splitField` into one dataset per distinct value —
 * always, for every type — but only eight of the twenty-two drawing functions
 * in `chart-svg.js` look past `data.datasets[0]`. A pie, a line or a treemap
 * handed four series silently draws one of them, and "silently draws one of
 * them" is the same class of lie as being shown a bar when you asked for a
 * Sankey.
 *
 * Read off `chart-svg.js` by which functions iterate `datasets` — grouped bars
 * (`barChartSVG`), both stacks, the stacked area, the slope, the radar, the
 * box plot and the heat map, where each dataset is a row. The claim is
 * MEASURED rather than trusted: `tests/grid/chart-element-props.test.js`
 * renders every renderable type with one dataset and with two and asserts the
 * mark count rises exactly for the types named here, so a renderer that gains
 * or loses multi-series support without this list moving is a red test.
 */
export const MULTI_SERIES_DRAWINGS = Object.freeze([
  'bar', 'stacked', 'hstacked', 'stacked-area', 'slope', 'radar', 'boxplot', 'heatmap',
]);

/**
 * True if `chartType` draws more than the first series.
 *
 * Takes a registry TYPE id (`'stacked-column'`) or a raw drawing name, the same
 * two vocabularies `renderChartSVG` accepts, so a caller never has to know
 * which side of `RENDERABLE_CHART_TYPES` it is holding.
 */
export function drawsEverySeries(chartType) {
  const drawing = RENDERABLE_CHART_TYPES[chartType] || chartType;
  return MULTI_SERIES_DRAWINGS.includes(drawing);
}

/**
 * The DRAWINGS in which one mark stands for exactly one category value.
 *
 * This is the same discipline as `MULTI_SERIES_DRAWINGS` one layer along, and
 * it exists because a page Chart's segments are now clickable: clicking one
 * filters the page to the records behind it. That promise is only true where a
 * mark IS a category, and for more than half of the twenty-two drawings it is
 * not:
 *
 *  - a **line**, **area**, **stacked area**, **slope**, **sparkline** and
 *    **scatter** draw a path or a point cloud. There is no per-category mark to
 *    press, and a click on a polyline cannot say which vertex was meant.
 *  - a **histogram** bins a continuous measure, so its bars are ranges rather
 *    than values — `Amount = "10–20"` is not a filter any engine can evaluate.
 *  - a **waterfall** draws deltas against a running total, and its last bar is
 *    frequently the total itself; filtering to it would answer a different
 *    question from the one the bar shows.
 *  - a **gauge**, **KPI**, **radial bar**, **radar**, **box plot** and
 *    **heat map** each collapse or reshape the categories (an aggregate of
 *    aggregates, a polygon over all of them, a five-number summary, a matrix
 *    cell that is a row × column pair rather than an x value).
 *
 * Drawing a cursor and a focus ring on a mark that cannot honour the click is
 * the "element that lies" this whole exercise is about, so those types simply
 * do not emit the affordance. The claim is MEASURED, not trusted:
 * `tests/grid/chart-element-props.test.js` renders every renderable type with
 * `pick` set and asserts segments appear exactly for the types named here.
 */
export const SEGMENT_DRAWINGS = Object.freeze([
  'bar', 'hbar', 'pie', 'donut', 'stacked', 'hstacked', 'lollipop', 'funnel', 'treemap',
]);

/**
 * True if `chartType` emits per-segment hooks when `renderChartSVG` is given a
 * `pick`. Accepts a registry type id or a raw drawing name, exactly like
 * `drawsEverySeries`.
 */
export function hasClickableSegments(chartType) {
  const drawing = RENDERABLE_CHART_TYPES[chartType] || chartType;
  return SEGMENT_DRAWINGS.includes(drawing);
}
