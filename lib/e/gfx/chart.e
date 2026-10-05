// Declarative chart geometry. The first slice keeps data borrowed and emits
// renderer-neutral marks; scene, PNG and widget adapters can consume Layout.
//
// The contract is intentionally small: one numeric x/y mapping, one Cartesian
// bounds rectangle, and caller-owned output. More chart families compose on it.

use e.algo.stat
use e.algo.sort
use e.algo.geo
use e.gfx.geometry
use e.gfx.paint
use e.math
use e.math.special
use e.math.filter as filter
use e.mem
use e.str
use e.text.layout as text_layout
use e.time

type Kind = enum u8 { Scatter, Line, Bar, Histogram, Step, Ecdf, Box, Density, Qq, Violin, Heatmap, Correlation, Area, Lollipop, ErrorBar, Band, Dumbbell, SlopeGraph, FrequencyPolygon, Rug, PointLine, Strip, Beeswarm, DotPlot, Waterfall, Bubble, Pp, Mosaic, Association }
type ScaleKind = enum u8 { Linear, Log10, Symlog }
type BinaryMetric = enum u8 { Roc, PrecisionRecall, CumulativeGain, Lift }
type ColorVision = enum u8 { Typical, Protan, Deutan, Tritan }
type Lab = struct { l: f64, a: f64, b: f64 }
type PaletteSeparation = struct { difference: f64, first: usize, second: usize }
type Scale = struct { kind: ScaleKind, reverse: bool, linthresh: f32 }
type Tick = struct { value: f32, fraction: f32 }
type DateTick = struct { date: time.Date, fraction: f32 }
type Coord = struct { x: f32, y: f32 }
type LabelAlign = enum u8 { Left, Center, Right }
type Label = struct { text: str, anchor: Coord, align: LabelAlign }
type LegendItem = struct { swatch: geometry.Rect, label: Label }
type WrappedLegend = struct { items: []LegendItem, rows: usize }
type ClassLegend = struct { swatches: []geometry.Rect, breaks: []Tick }
type LabelPlacement = struct { label: Label, box: geometry.Rect, placed: bool, slot: u8 }
type PointLabels = struct { labels: []LabelPlacement, placed: usize }
type NetworkLayout = struct { nodes: []Coord, links: Layout }
type Segment = struct { from: Coord, to: Coord }
type Cell = struct { rect: geometry.Rect, value: f32 }
type ContourVertex = struct { point: Coord, value: f64 }
type SunburstArc = struct { start: f64, end: f64, next: f64 }
type SankeyNode = struct { incoming: f64, outgoing: f64, in_used: f64, out_used: f64 }
type TargetStatus = struct { delta: f32, achieved: bool }
type CloudWord = struct { label: Label, size: f32, box: geometry.Rect }
type StateSpan = struct { row: usize, start: f64, end: f64, state: usize }
type GanttTask = struct { row: usize, start: f64, end: f64, complete: f32 }
type ResourceSpan = struct { start: f64, end: f64, units: f64 }
type SwimlaneStep = struct { lane: usize, stage: usize }
type SwimlaneLink = struct { from: usize, to: usize }
type KanbanCard = struct { column: usize, height: f32 }
type KanbanStatus = struct { count: usize, limit: usize, exceeded: bool }
type CpmActivity = struct { optimistic: f64, likely: f64, pessimistic: f64 }
type CpmDependency = struct { from: usize, to: usize }
type CpmTiming = struct { expected: f64, variance: f64, earliest_start: f64, earliest_finish: f64, latest_start: f64, latest_finish: f64, slack: f64, stage: usize, critical: bool }
type CpmSummary = struct { duration: f64, critical_count: usize, stages: usize }
type CpmWork = struct { indegree: []usize, head: []usize, next: []usize, order: []usize }
type ValueStreamStep = struct { process_time: f64, value_added_time: f64, wait_before: f64, good_fraction: f64 }
type ValueStreamSummary = struct { process_time: f64, value_added_time: f64, wait_time: f64, lead_time: f64, process_cycle_efficiency: f64, rolled_yield: f64 }
type ValueStreamLayout = struct { nodes: Layout, connectors: Layout, process: Layout, waiting: Layout, summary: ValueStreamSummary }
type ValueStreamFlow = enum u8 { Push, Fifo, Pull }
type ValueStreamWork = struct { boxes: []geometry.Rect, arrows: []Segment, process_bars: []geometry.Rect, wait_bars: []geometry.Rect }
type FutureValueStreamWork = struct {
    current: ValueStreamWork, future: ValueStreamWork,
    fifo_cues: []geometry.Rect, pull_cues: []geometry.Rect,
    over_takt: []geometry.Rect, pacemaker: []geometry.Rect,
}
type FutureValueStreamLayout = struct {
    current: ValueStreamLayout, future: ValueStreamLayout,
    fifo: Layout, pull: Layout, over_takt: Layout, pacemaker: Layout,
    takt_time: f64, lead_reduction: f64, pce_gain: f64, yield_gain: f64,
}
type CapTableSummary = struct {
    before_shares: u64, after_shares: u64, pool_added: u64, investor_added: u64,
    incumbent_fraction: f64, pool_fraction: f64, investor_fraction: f64,
}
type CapTableWork = struct {
    before_bars: []geometry.Rect, after_bars: []geometry.Rect,
    before_layers: []Layout, after_layers: []Layout,
    before_fractions: []f64, after_fractions: []f64,
    bridge_bars: []geometry.Rect, bridge_links: []Segment,
}
type CapTableLayout = struct {
    before: []Layout, after: []Layout, bridge: Layout,
    before_fractions: []f64, after_fractions: []f64,
    pool_present: bool, investor_present: bool, summary: CapTableSummary,
}
type TornadoCase = struct { low_result: f64, high_result: f64 }
type TornadoLayout = struct { low: Layout, high: Layout, baseline: Layout, order: []usize, minimum: f64, maximum: f64 }
type MonteCarloLayout = struct { histogram: Layout, cdf: Layout, histogram_threshold: Layout, cdf_threshold: Layout, sorted: []f64, counts: []u64, at_or_below: u64, probability: f64 }
type SipocEntry = struct { column: usize }
type SipocLayout = struct { bands: Layout, headers: Layout, cards: Layout, connectors: Layout, max_rows: usize }
type DecisionKind = enum u8 { Choice, Chance, Outcome }
type DecisionNode = struct { kind: DecisionKind, payoff: f64 }
type DecisionEdge = struct { from: usize, to: usize, probability: f64 }
type DecisionValue = struct { expected: f64, selected_edge: usize, depth: usize, leaf_count: usize, leaf_start: usize }
type DecisionTreeWork = struct { indegree: []usize, head: []usize, next: []usize, order: []usize }
type DecisionTreeSummary = struct { expected: f64, depth: usize, leaves: usize }
type OrgLink = struct { manager: usize, report: usize }
type OrgPlacement = struct { depth: usize, leaf_start: usize, leaf_count: usize, direct_reports: usize }
type OrgWork = struct { indegree: []usize, head: []usize, next: []usize, order: []usize }
type OrgLayout = struct { nodes: Layout, connectors: Layout, levels: usize, leaves: usize }
type AggregateTreeLayout = struct { nodes: Layout, value_bars: Layout, connectors: Layout, levels: usize, leaves: usize }
type DependencyLink = struct { from: usize, to: usize }
type DependencyWork = struct { indegree: []usize, head: []usize, next: []usize, order: []usize, stage: []usize, stage_counts: []usize, stage_used: []usize }
type DependencyLayout = struct { nodes: Layout, connectors: Layout, stages: usize, sources: usize }
type FlowKind = enum u8 { Terminal, Process, Decision }
type FlowPort = enum u8 { Top, Right, Bottom, Left }
type FlowNode = struct { kind: FlowKind, center: Coord }
type FlowLink = struct { from: usize, to: usize, exit: FlowPort, entry: FlowPort }
type FlowLayout = struct { nodes: []Layout, connectors: Layout }
type MachineState = struct { center: Coord, initial: bool, final: bool }
type MachineTransition = struct { from: usize, to: usize, event: usize }
type MachineLayout = struct { states: []Layout, transitions: Layout, initial_marker: Layout, final_rings: Layout, event_labels: []Label }
type SequenceKind = enum u8 { Call, Return, Async }
type SequenceMessage = struct { from: usize, to: usize, kind: SequenceKind, text: str }
type SequenceActivation = struct { participant: usize, first: usize, last: usize }
type SequenceLayout = struct { headers: Layout, lifelines: Layout, activations: Layout, messages: []Layout, labels: []Label }
type EntityTable = struct { name: str, center: Coord }
type EntityKey = enum u8 { None, Primary, Foreign }
type EntityField = struct { table: usize, name: str, key: EntityKey }
type EntityCardinality = enum u8 { One, ZeroOne, Many, ZeroMany }
type EntityRelation = struct { from: usize, to: usize, from_card: EntityCardinality, to_card: EntityCardinality, name: str }
type EntityLayout = struct { tables: Layout, headers: Layout, connectors: Layout, table_labels: []Label, field_labels: []Label, key_labels: []Label, relation_labels: []Label }
type BranchStep = struct { process_time: f64, good_fraction: f64 }
type BranchRoute = struct { from: usize, to: usize, fraction: f64 }
type BranchWork = struct { indegree: []usize, head: []usize, next: []usize, order: []usize, stage: []usize, stage_counts: []usize, stage_used: []usize, flow: []f64, branch_sum: []f64 }
type BranchSummary = struct { output_fraction: f64, expected_processing_time: f64, stages: usize, sinks: usize }
type BranchLayout = struct { nodes: Layout, connectors: Layout, summary: BranchSummary }
type FishboneCause = struct { category: usize, parent: i32, text: str }
type FishboneLayout = struct { spine: Layout, ribs: Layout, causes: Layout, head: Layout, labels: []Label }
type CauseTreeNode = struct { parent: i32, text: str }
type CauseTreePlacement = struct { depth: usize, leaf_start: usize, leaf_count: usize, children: usize }
type CauseTreeWork = struct { placements: []CauseTreePlacement, cursor: []usize }
type CauseTreeLayout = struct { nodes: Layout, connectors: Layout, labels: []Label, levels: usize, leaves: usize }
type StemLeafRow = struct { stem: i64, first: usize, count: usize, baseline: f32 }
type StemLeafLayout = struct { rows: []StemLeafRow, leaves: []u8, divider: Segment, leaf_start: f32, leaf_step: f32, leaf_unit: f64 }
type RangeInterval = struct { row: usize, lower: f64, upper: f64 }
type RangeIntervalLayout = struct { ranges: Layout, caps: Layout }
type FootballFieldLayout = struct { ranges: Layout, caps: Layout, benchmark: Layout }
type ProbabilityFamily = enum u8 { Normal, Exponential }
type ProbabilityLayout = struct { observations: Layout, reference: Layout, probability_ticks: []Tick }
type GageRrLayout = struct { contribution: Layout, study_variation: Layout, percentages: []f32 }
type MultiVariStorage = struct { raw_points: []Coord, cell_points: []Coord, cell_lines: []Segment, group_points: []Coord, group_lines: []Segment, cell_means: []f64, group_means: []f64 }
type MultiVariLayout = struct { observations: Layout, cells: Layout, within: Layout, groups: Layout, cell_means: []f64, group_means: []f64 }
type MainEffectsStorage = struct { points: []Coord, lines: []Segment, references: []Segment, means: []f64, counts: []usize }
type MainEffectsLayout = struct { levels: Layout, connections: Layout, reference: Layout, means: []f64, counts: []usize, grand_mean: f64 }
type AnomStorage = struct { points: []Coord, signals: []Coord, upper: []Segment, lower: []Segment, center: []Segment, means: []f64, counts: []usize, upper_limits: []f64, lower_limits: []f64 }
type AnomLayout = struct { groups: Layout, signals: Layout, upper: Layout, lower: Layout, center: Layout, means: []f64, counts: []usize, upper_limits: []f64, lower_limits: []f64, grand_mean: f64, pooled_sd: f64, critical: f64 }
type HotellingStorage = struct { means: []f64, covariance: []f64, factor: []f64, residual: []f64, scores: []f64, points: []Coord, segments: []Segment, signals: []Coord, upper: []Segment }
type HotellingLayout = struct { trace: Layout, signals: Layout, upper: Layout, means: []f64, covariance: []f64, scores: []f64, upper_limit: f64, historical_count: usize, phase_two: bool }
type GeneralizedVarianceStorage = struct { covariance: []f64, pooled: []f64, factor: []f64, determinants: []f64, points: []Coord, segments: []Segment, signals: []Coord, upper: []Segment, lower: []Segment, center: []Segment }
type GeneralizedVarianceLayout = struct { trace: Layout, signals: Layout, upper: Layout, lower: Layout, center: Layout, determinants: []f64, pooled_covariance: []f64, center_value: f64, lower_limit: f64, upper_limit: f64, b1: f64, b2: f64, b3: f64, phase_one_count: usize, phase_two_count: usize }
type MewmaStorage = struct { means: []f64, covariance: []f64, factor: []f64, state: []f64, residual: []f64, smoothed: []f64, scores: []f64, points: []Coord, segments: []Segment, signals: []Coord, upper: []Segment }
type MewmaLayout = struct { trace: Layout, signals: Layout, upper: Layout, means: []f64, covariance: []f64, smoothed: []f64, scores: []f64, upper_limit: f64, lambda: f64, historical_count: usize, phase_two: bool }
type InteractionStorage = struct { points: []Coord, lines: []Segment, means: []f64, counts: []usize, series: []Layout }
type InteractionLayout = struct { series: []Layout, means: []f64, counts: []usize }
type CubePlotStorage = struct { vertices: []Coord, edges: []Segment, means: []f64, counts: []usize }
type CubePlotLayout = struct { vertices: Layout, frame: Layout, means: []f64, counts: []usize }
type SpectrogramLayout = struct { matrix: MatrixLayout, time_start: f64, time_end: f64, frequency_max: f64 }
type WaterfallSpectrumStorage = struct { points: []Coord, segments: []Segment, traces: []Layout, frame_indices: []usize }
type WaterfallSpectrumLayout = struct { traces: []Layout, frame_indices: []usize, value_min: f32, value_max: f32 }
type BodeStorage = struct { magnitude_points: []Coord, magnitude_segments: []Segment, phase_points: []Coord, phase_segments: []Segment, magnitude_db: []f64, phase_degrees: []f64 }
type BodeLayout = struct { magnitude: Layout, phase: Layout, magnitude_bounds: geometry.Rect, phase_bounds: geometry.Rect, magnitude_db: []f64, phase_degrees: []f64, frequency_min: f64, frequency_max: f64 }
type NyquistStorage = struct { positive_points: []Coord, positive_segments: []Segment, negative_points: []Coord, negative_segments: []Segment, critical_point: []Coord }
type NyquistLayout = struct { positive: Layout, negative: Layout, critical: Layout, frequency_min: f64, frequency_max: f64 }
type Camera3d = struct { azimuth_degrees: f64, elevation_degrees: f64, distance: f64 }
type Projection3d = struct { sin_azimuth: f64, cos_azimuth: f64, sin_elevation: f64, cos_elevation: f64, distance: f64 }
type Viewport3d = struct { projection: Projection3d, u_center: f64, v_center: f64, scale: f64, x_center: f64, y_center: f64 }
type Scatter3dStorage = struct { points: []Coord, depths: []f64, order: []usize, bubbles: []geometry.Rect, corners: []Coord, edges: []Segment }
type Scatter3dLayout = struct { marks: Layout, frame: Layout, points: []Coord, depths: []f64, order: []usize, corners: []Coord, x_min: f64, x_max: f64, y_min: f64, y_max: f64, z_min: f64, z_max: f64 }
type Scatter3dOrder = struct { depths: []f64 }
type Histogram3dFace = enum u8 { Top, XSide, YSide }
type Histogram3dStorage = struct { counts: []u64, cells: []Cell, vertices: []Coord, faces: []Layout, depths: []f64, order: []usize, face_kinds: []Histogram3dFace, corners: []Coord, edges: []Segment }
type Histogram3dLayout = struct { faces: []Layout, depths: []f64, order: []usize, face_kinds: []Histogram3dFace, counts: []u64, frame: Layout, corners: []Coord, columns: usize, rows: usize, max_count: u64, total_count: u64 }
type Surface3dStorage = struct { points: []Coord, depths: []f64, face_vertices: []Coord, faces: []Layout, face_depths: []f64, face_values: []f64, order: []usize, wires: []Segment, corners: []Coord, edges: []Segment }
type Surface3dLayout = struct { faces: []Layout, face_depths: []f64, face_values: []f64, order: []usize, wireframe: Layout, frame: Layout, points: []Coord, depths: []f64, values: []const f64, corners: []Coord, columns: usize, rows: usize, value_min: f64, value_max: f64 }
type SpineLayout = struct { categories: []Layout, column_totals: []f64, grand_total: f64 }
type HexCell = struct { center: Coord, count: u64 }
type HexbinLayout = struct { cells: []HexCell, hexes: []Layout, max_count: u64, total_count: u64 }
type RiskPoint = struct { likelihood: usize, impact: usize }
type CalendarDay = struct { offset: usize, value: f64 }
type TimelineEvent = struct { time: f64, row: usize }
type Spec = struct { kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32, baseline: f32, bar_width: f32, x_scale: Scale, y_scale: Scale }
type Layout = struct { kind: Kind, coords: []Coord, segments: []Segment, bars: []geometry.Rect, x_min: f32, x_max: f32, y_min: f32, y_max: f32 }
type CategoryFacetLayout = struct { panels: []geometry.Rect, marks: []Layout, strips: []Label, counts: []usize }
type MaskedScatterLayout = struct { marks: Layout, row_ids: []usize, omitted: usize }
type SelectionHit = struct { mark_index: usize, source_row: usize, distance_squared: f64 }
type MatrixLayout = struct { kind: Kind, cells: []Cell, columns: usize, rows: usize, value_min: f32, value_max: f32 }
type Bin2dLayout = struct { matrix: MatrixLayout, counts: []u64, max_count: u64, total_count: u64 }
type Density2dLayout = struct { contours: []Layout, grid: []f64, cutoffs: []f64, peak: f64 }
type RaincloudLayout = struct { cloud: Layout, drops: Layout, summary: Layout }
type MarginalHistogramLayout = struct { scatter: Layout, top: Layout, right: Layout }
type DoseResponseLayout = struct { observations: Layout, curve: Layout }
type InfluenceLayout = struct { points: Layout, bubbles: Layout, guides: Layout, max_cook: f64 }
type CapabilitySixpackStorage = struct {
    moving: []f64,
    individual_points: []Coord, individual_lines: []Segment,
    range_points: []Coord, range_lines: []Segment,
    recent_points: []Coord,
    histogram_counts: []u64, histogram_bars: []geometry.Rect,
    within_curve: []Segment, overall_curve: []Segment,
    probability_points: []Coord, probability_reference: []Segment,
    interval_bars: []geometry.Rect, guides: []Segment,
}
type CapabilitySixpackLayout = struct {
    individuals: Layout, moving_range: Layout, recent: Layout,
    histogram: Layout, within_curve: Layout, overall_curve: Layout,
    probability: Layout, intervals: Layout, guides: Layout,
    summary: stat.NormalCapability,
}
type NormalCapabilityStorage = struct {
    moving: []f64, counts: []u64, bars: []geometry.Rect,
    within_curve: []Segment, overall_curve: []Segment, guides: []Segment,
}
type NormalCapabilityLayout = struct {
    histogram: Layout, within_curve: Layout, overall_curve: Layout, guides: Layout,
    summary: stat.NormalCapability, performance: stat.CapabilityPerformance,
}
type LognormalCapabilityStorage = struct {
    counts: []u64, bars: []geometry.Rect, fit_curve: []Segment, guides: []Segment,
}
type LognormalCapabilityLayout = struct {
    histogram: Layout, fit_curve: Layout, guides: Layout, summary: stat.LognormalCapability,
}
type BinomialCapabilityStorage = struct {
    controls: []stat.AttributeControlPoint, cumulative_rates: []f64,
    p_points: []Coord, p_lines: []Segment,
    cumulative_points: []Coord, cumulative_lines: []Segment,
    upper_limit: []Segment, lower_limit: []Segment,
    guides: []Segment, signal_points: []Coord,
}
type BinomialCapabilityLayout = struct {
    p_chart: Layout, cumulative: Layout, upper_limit: Layout, lower_limit: Layout,
    guides: Layout, signals: Layout, summary: stat.BinomialCapability,
}
type BatchCapabilityStorage = struct {
    batch_means: []f64, batch_spreads: []f64,
    mean_points: []Coord, mean_lines: []Segment, spread_bars: []geometry.Rect,
    guides: []Segment,
}
type BatchCapabilityLayout = struct {
    means: Layout, spreads: Layout, guides: Layout, summary: stat.BatchCapability,
}
type GageLinearityStorage = struct {
    biases: []f64, mean_biases: []f64, fitted_biases: []f64,
    ci_lower: []f64, ci_upper: []f64,
    raw_points: []Coord, mean_points: []Coord,
    fit_segments: []Segment, ci_segments: []Segment, zero_guide: []Segment,
}
type GageLinearityLayout = struct {
    observations: Layout, means: Layout, fit: Layout, confidence: Layout,
    zero_line: Layout, summary: stat.GageLinearity,
}
type AttributeAgreementStorage = struct {
    within_rates: []stat.AttributeAgreementRate, standard_rates: []stat.AttributeAgreementRate,
    within_points: []Coord, standard_points: []Coord,
    within_intervals: []Segment, standard_intervals: []Segment,
}
type AttributeAgreementLayout = struct {
    within: Layout, within_intervals: Layout,
    versus_standard: Layout, standard_intervals: Layout,
    summary: stat.AttributeAgreement,
}
type GageRunStorage = struct {
    operator_points: []Coord, operator_layouts: []Layout,
    part_centers: []Coord, part_dividers: []Segment, mean_guide: []Segment,
}
type GageRunLayout = struct {
    operators: []Layout, part_centers: []Coord,
    dividers: Layout, reference: Layout, summary: stat.GageRunSummary,
}
type MapVertex = struct { lon: f64, lat: f64 }
type MapRegion = struct { key: str }
type MapMetric = struct { key: str, value: f64 }
type MapRing = struct { region: usize, first: usize, count: usize, hole: bool }
type MapProjectedRing = struct { first: usize, count: usize, hole: bool, reverse: bool }
type MapRegionLayout = struct {
    key: str, rings: []const MapProjectedRing, points: []const Coord,
    has_value: bool, value: f64, fraction: f32,
}
type ChoroplethStorage = struct { points: []Coord, rings: []MapProjectedRing, regions: []MapRegionLayout }
type ChoroplethLayout = struct { regions: []MapRegionLayout, minimum: f64, maximum: f64, has_values: bool }
type MapSite = struct { key: str, lon: f64, lat: f64, value: f64, present: bool }
type ProportionalMapLayout = struct { marks: Layout, maximum: f64, present_count: usize }
type ReportCellKind = enum u8 { Corner, ColumnHeader, RowHeader, Body, RowTotal, ColumnTotal, GroupSubtotal, GrandTotal }
type ReportBarScope = enum u8 { None, Row, Global }
type ReportCell = struct {
    rect: geometry.Rect, bar: geometry.Rect, kind: ReportCellKind,
    value: f64, present: bool, source: usize,
}
type CrossTabStorage = struct { counts: []u64, row_totals: []u64, column_totals: []u64, cells: []ReportCell }
type CrossTabLayout = struct { cells: []ReportCell, summary: stat.CrossTabSummary, display_rows: usize, display_columns: usize }
type MatrixReportStorage = struct {
    aggregates: []stat.ReportAggregate, row_totals: []stat.ReportAggregate,
    column_totals: []stat.ReportAggregate, group_aggregates: []stat.ReportAggregate,
    group_totals: []stat.ReportAggregate, cells: []ReportCell,
}
type MatrixReportLayout = struct {
    cells: []ReportCell, grand: stat.ReportAggregate,
    display_rows: usize, display_columns: usize, group_count: usize,
}

fn report_fill_index(kind: ReportCellKind) -> usize {
    if kind == .Corner { ret 0usize }
    if kind == .ColumnHeader { ret 1usize }
    if kind == .RowHeader { ret 2usize }
    if kind == .Body { ret 3usize }
    if kind == .RowTotal { ret 4usize }
    if kind == .ColumnTotal { ret 5usize }
    if kind == .GroupSubtotal { ret 6usize }
    ret 7usize
}
type FourfoldLayout = struct { wedges: []Layout, rings: Layout, odds_ratio: f64, ci_low: f64, ci_high: f64 }
type HorizonPatch = struct { layout: Layout, band: usize, negative: bool }
error Invalid
error Empty
error TooLarge

fn spec(kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32) -> Spec {
    let linear = Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    ret Spec { kind: kind, bounds: bounds, x: x, y: y, baseline: 0.0, bar_width: 0.0, x_scale: linear, y_scale: linear }
}

fn finite(v: f32) -> bool {
    ret v == v && v - v == 0.0
}

fn finite64(v: f64) -> bool {
    ret v == v && v - v == 0.0f64
}

fn valid_bounds(bounds: geometry.Rect) -> bool {
    ret finite(bounds.x) && finite(bounds.y) && finite(bounds.width) && finite(bounds.height) && bounds.width > 0.0 && bounds.height > 0.0
}

// WCAG relative luminance of the bytes the scene/PNG and SVG adapters write:
// each channel rounds as scene.channel_byte does, then linearizes as sRGB.
fn rendered_channel(c: f32) -> f64 {
    ret f64(paint.srgb_to_linear(f32(u32(c * 255.0 + 0.5)) / 255.0))
}

fn rendered_luminance(color: paint.Color) -> f64 {
    ret 0.2126f64 * rendered_channel(color.red) + 0.7152f64 * rendered_channel(color.green) + 0.0722f64 * rendered_channel(color.blue)
}

fn luminance_contrast(first: f64, second: f64) -> f64 {
    var brighter = first
    var darker = second
    if second > first {
        brighter = second
        darker = first
    }
    ret (brighter + 0.05f64) / (darker + 0.05f64)
}

fn rendered_contrast_ratio(first: paint.Color, second: paint.Color) -> (f64, err) {
    if !paint.color_ok(first) || !paint.color_ok(second) || first.alpha != 1.0 || second.alpha != 1.0 { ret (0.0f64, Invalid) }
    ret (luminance_contrast(rendered_luminance(first), rendered_luminance(second)), ok)
}

// Six qualitative seed hues move toward black or white, whichever contrasts
// more with the opaque background, only as far as 4.5:1 needs. One of the two
// always reaches at least 4.58:1. Series still need labels or shapes: a
// palette cannot make color the sole cue.
fn accessible_palette(background: paint.Color, out: []paint.Color) -> ([]paint.Color, err) {
    if !paint.color_ok(background) || background.alpha != 1.0 { ret (zero, Invalid) }
    if out.len < 6usize { ret (zero, TooLarge) }
    let seeds = [6]paint.Color{
        paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 1.0),
        paint.rgba(213.0 / 255.0, 94.0 / 255.0, 0.0, 1.0),
        paint.rgba(0.0, 158.0 / 255.0, 115.0 / 255.0, 1.0),
        paint.rgba(142.0 / 255.0, 68.0 / 255.0, 173.0 / 255.0, 1.0),
        paint.rgba(179.0 / 255.0, 38.0 / 255.0, 62.0 / 255.0, 1.0),
        paint.rgba(179.0 / 255.0, 107.0 / 255.0, 0.0, 1.0),
    }
    let background_luminance = rendered_luminance(background)
    var extreme = 0.0f32
    if luminance_contrast(1.0f64, background_luminance) > luminance_contrast(0.0f64, background_luminance) { extreme = 1.0 }
    var i = 0usize
    while i < seeds.len {
        let seed = seeds[i]
        var chosen = seed
        if luminance_contrast(rendered_luminance(seed), background_luminance) < 4.5f64 {
            var low = 0.0f32
            var high = 1.0f32
            var step = 0usize
            while step < 20usize {
                let amount = (low + high) * 0.5
                let trial = paint.rgba(seed.red + (extreme - seed.red) * amount, seed.green + (extreme - seed.green) * amount, seed.blue + (extreme - seed.blue) * amount, 1.0)
                if luminance_contrast(rendered_luminance(trial), background_luminance) >= 4.5f64 {
                    high = amount
                } else {
                    low = amount
                }
                step += 1usize
            }
            chosen = paint.rgba(seed.red + (extreme - seed.red) * high, seed.green + (extreme - seed.green) * high, seed.blue + (extreme - seed.blue) * high, 1.0)
        }
        out[i] = chosen
        i += 1usize
    }
    ret (out[..seeds.len], ok)
}

fn srgb_linear64(c: f32) -> f64 {
    let v = f64(c)
    if v <= 0.04045f64 { ret v / 12.92f64 }
    ret math.pow[f64]((v + 0.055f64) / 1.055f64, 2.4f64)
}

// Dichromat simulation after Vienot, Brettel and Mollon (1999): linear RGB to
// Hunt-Pointer-Estevez LMS, the missing cone response replaced by the plane
// through white and blue (protan, deutan) or white and red (tritan), and back.
// Each kind folds into one linear-RGB matrix; scripts/chart_cvd_reference.py derives
// them. Severity below 1 blends toward the original in linear RGB, the usual
// approximation for anomalous trichromacy. Tritan is the least accurate of
// the three in this model.
fn simulate_color_vision(color: paint.Color, vision: ColorVision, severity: f32) -> (paint.Color, err) {
    if !paint.color_ok(color) || !(severity >= 0.0 && severity <= 1.0) { ret (zero, Invalid) }
    if vision == .Typical || severity == 0.0 { ret (color, ok) }
    var m = [9]f64{ 0.11238292f64, 0.88761708f64, 0.0f64, 0.11238292f64, 0.88761708f64, 0.0f64, 0.004005757f64, -0.004005757f64, 1.0f64 }
    if vision == .Deutan {
        m = [9]f64{ 0.292750016f64, 0.707249984f64, 0.0f64, 0.292750016f64, 0.707249984f64, 0.0f64, -0.022336501f64, 0.022336501f64, 1.0f64 }
    } else if vision == .Tritan {
        m = [9]f64{ 1.0f64, 0.144613171f64, -0.144613171f64, 0.0f64, 0.859235494f64, 0.140764506f64, 0.0f64, 0.859235494f64, 0.140764506f64 }
    }
    let r = srgb_linear64(color.red)
    let g = srgb_linear64(color.green)
    let b = srgb_linear64(color.blue)
    let s = f64(severity)
    let red = r + (m[0usize] * r + m[1usize] * g + m[2usize] * b - r) * s
    let green = g + (m[3usize] * r + m[4usize] * g + m[5usize] * b - g) * s
    let blue = b + (m[6usize] * r + m[7usize] * g + m[8usize] * b - b) * s
    ret (paint.rgba(paint.linear_to_srgb(f32(red)), paint.linear_to_srgb(f32(green)), paint.linear_to_srgb(f32(blue)), color.alpha), ok)
}

fn lab_f(t: f64) -> f64 {
    if t > 0.008856451679035631f64 { ret math.pow[f64](t, 1.0f64 / 3.0f64) }
    ret t / 0.12841854934601665f64 + 4.0f64 / 29.0f64
}

// CIELAB under D65 of an sRGB colour (alpha ignored).
fn color_lab(color: paint.Color) -> (Lab, err) {
    if !paint.color_ok(color) { ret (zero, Invalid) }
    let r = srgb_linear64(color.red)
    let g = srgb_linear64(color.green)
    let b = srgb_linear64(color.blue)
    let x = lab_f((0.4124564f64 * r + 0.3575761f64 * g + 0.1804375f64 * b) / 0.95047f64)
    let y = lab_f(0.2126729f64 * r + 0.7151522f64 * g + 0.0721750f64 * b)
    let z = lab_f((0.0193339f64 * r + 0.1191920f64 * g + 0.9503041f64 * b) / 1.08883f64)
    ret (Lab { l: 116.0f64 * y - 16.0f64, a: 500.0f64 * (x - y), b: 200.0f64 * (y - z) }, ok)
}

fn hue_degrees(b: f64, a: f64) -> f64 {
    if a == 0.0f64 && b == 0.0f64 { ret 0.0f64 }
    var h = math.atan2[f64](b, a) * 180.0f64 / 3.141592653589793f64
    if h < 0.0f64 { h += 360.0f64 }
    ret h
}

fn radians(degrees: f64) -> f64 { ret degrees * 3.141592653589793f64 / 180.0f64 }

// CIEDE2000 colour difference (Sharma, Wu and Dalal 2005), kL = kC = kH = 1.
fn ciede2000(first: Lab, second: Lab) -> f64 {
    let pow25 = 6103515625.0f64
    let c1 = math.sqrt[f64](first.a * first.a + first.b * first.b)
    let c2 = math.sqrt[f64](second.a * second.a + second.b * second.b)
    let c_mean7 = math.pow[f64]((c1 + c2) / 2.0f64, 7.0f64)
    let g = 0.5f64 * (1.0f64 - math.sqrt[f64](c_mean7 / (c_mean7 + pow25)))
    let a1 = (1.0f64 + g) * first.a
    let a2 = (1.0f64 + g) * second.a
    let c1p = math.sqrt[f64](a1 * a1 + first.b * first.b)
    let c2p = math.sqrt[f64](a2 * a2 + second.b * second.b)
    let h1 = hue_degrees(first.b, a1)
    let h2 = hue_degrees(second.b, a2)
    var dh = 0.0f64
    var h_mean = h1 + h2
    if c1p * c2p != 0.0f64 {
        dh = h2 - h1
        if dh > 180.0f64 { dh -= 360.0f64 } else if dh < -180.0f64 { dh += 360.0f64 }
        if math.abs[f64](h1 - h2) <= 180.0f64 {
            h_mean = (h1 + h2) / 2.0f64
        } else if h1 + h2 < 360.0f64 {
            h_mean = (h1 + h2 + 360.0f64) / 2.0f64
        } else {
            h_mean = (h1 + h2 - 360.0f64) / 2.0f64
        }
    }
    let d_l = second.l - first.l
    let d_c = c2p - c1p
    let d_h = 2.0f64 * math.sqrt[f64](c1p * c2p) * math.sin[f64](radians(dh / 2.0f64))
    let l_mean = (first.l + second.l) / 2.0f64
    let c_mean = (c1p + c2p) / 2.0f64
    let t = 1.0f64 - 0.17f64 * math.cos[f64](radians(h_mean - 30.0f64)) + 0.24f64 * math.cos[f64](radians(2.0f64 * h_mean)) + 0.32f64 * math.cos[f64](radians(3.0f64 * h_mean + 6.0f64)) - 0.20f64 * math.cos[f64](radians(4.0f64 * h_mean - 63.0f64))
    let theta = 30.0f64 * math.exp[f64](-((h_mean - 275.0f64) / 25.0f64) * ((h_mean - 275.0f64) / 25.0f64))
    let c_mean_p7 = math.pow[f64](c_mean, 7.0f64)
    let r_c = 2.0f64 * math.sqrt[f64](c_mean_p7 / (c_mean_p7 + pow25))
    let l50 = (l_mean - 50.0f64) * (l_mean - 50.0f64)
    let s_l = 1.0f64 + 0.015f64 * l50 / math.sqrt[f64](20.0f64 + l50)
    let s_c = 1.0f64 + 0.045f64 * c_mean
    let s_h = 1.0f64 + 0.015f64 * c_mean * t
    let r_t = -math.sin[f64](radians(2.0f64 * theta)) * r_c
    let lt = d_l / s_l
    let ct = d_c / s_c
    let ht = d_h / s_h
    ret math.sqrt[f64](lt * lt + ct * ct + ht * ht + r_t * ct * ht)
}

// The closest pair of a palette as seen with the given colour vision: the
// smallest CIEDE2000 difference between simulated colours and its indices.
fn palette_separation(colors: []const paint.Color, vision: ColorVision, severity: f32) -> (PaletteSeparation, err) {
    if colors.len < 2usize { ret (zero, Empty) }
    var best = PaletteSeparation { difference: 0.0f64, first: 0usize, second: 0usize }
    var found = false
    var i = 0usize
    while i < colors.len {
        let (seen_i, i_error) = simulate_color_vision(colors[i], vision, severity)
        if i_error != ok { ret (zero, i_error) }
        let (lab_i, lab_i_error) = color_lab(seen_i)
        if lab_i_error != ok { ret (zero, lab_i_error) }
        var j = i + 1usize
        while j < colors.len {
            let (seen_j, j_error) = simulate_color_vision(colors[j], vision, severity)
            if j_error != ok { ret (zero, j_error) }
            let (lab_j, lab_j_error) = color_lab(seen_j)
            if lab_j_error != ok { ret (zero, lab_j_error) }
            let difference = ciede2000(lab_i, lab_j)
            if !found || difference < best.difference {
                best = PaletteSeparation { difference: difference, first: i, second: j }
                found = true
            }
            j += 1usize
        }
        i += 1usize
    }
    ret (best, ok)
}

fn extent(values: []const f32) -> (f32, f32, err) {
    if values.len == 0usize { ret (0.0, 0.0, Empty) }
    if !finite(values[0usize]) { ret (0.0, 0.0, Invalid) }
    var lo = values[0usize]
    var hi = lo
    var i = 1usize
    while i < values.len {
        if !finite(values[i]) { ret (0.0, 0.0, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    ret (lo, hi, ok)
}

fn mapped(value: f32, lo: f32, hi: f32, start: f32, size: f32) -> f32 {
    ret start + (value - lo) / (hi - lo) * size
}

fn valid_scale(scale: Scale, lo: f32, hi: f32) -> bool {
    if !finite(lo) || !finite(hi) || !(hi > lo) { ret false }
    if scale.kind == .Log10 { ret lo > 0.0 }
    if scale.kind == .Symlog { ret finite(scale.linthresh) && scale.linthresh > 0.0 }
    ret true
}

fn transformed(value: f32, scale: Scale) -> f64 {
    if scale.kind == .Log10 { ret math.log10[f64](f64(value)) }
    if scale.kind == .Symlog {
        let unit = f64(value) / f64(scale.linthresh)
        if unit < 0.0f64 { ret 0.0f64 - math.log10[f64](1.0f64 - unit) }
        ret math.log10[f64](1.0f64 + unit)
    }
    ret f64(value)
}

fn fraction(value: f32, lo: f32, hi: f32, scale: Scale) -> f32 {
    let t = f32((transformed(value, scale) - transformed(lo, scale)) / (transformed(hi, scale) - transformed(lo, scale)))
    if scale.reverse { ret 1.0 - t }
    ret t
}

fn x_position(s: *const Spec, value: f32, lo: f32, hi: f32) -> f32 {
    ret s.bounds.x + s.bounds.width * fraction(value, lo, hi, s.x_scale)
}

fn y_position(s: *const Spec, value: f32, lo: f32, hi: f32) -> f32 {
    ret s.bounds.y + s.bounds.height * (1.0 - fraction(value, lo, hi, s.y_scale))
}

// Even breaks in transformed space, with data values and normalized positions
// returned to the caller for grid, label and interaction adapters.
fn ticks(scale: Scale, lo: f32, hi: f32, out: []Tick) -> ([]Tick, err) {
    if out.len < 2usize { ret (zero, TooLarge) }
    if !valid_scale(scale, lo, hi) { ret (zero, Invalid) }
    let first = transformed(lo, scale)
    let span = transformed(hi, scale) - first
    var i = 0usize
    while i < out.len {
        let t = f64(i) / f64(out.len - 1usize)
        let transformed_value = first + span * t
        var value = transformed_value
        if scale.kind == .Log10 {
            value = math.pow[f64](10.0f64, transformed_value)
        } else if scale.kind == .Symlog {
            if transformed_value < 0.0f64 {
                value = f64(scale.linthresh) * (1.0f64 - math.pow[f64](10.0f64, 0.0f64 - transformed_value))
            } else {
                value = f64(scale.linthresh) * (math.pow[f64](10.0f64, transformed_value) - 1.0f64)
            }
        }
        var position = f32(t)
        if scale.reverse { position = 1.0 - position }
        out[i] = Tick { value: f32(value), fraction: position }
        i += 1usize
    }
    out[0usize].value = lo
    out[out.len - 1usize].value = hi
    ret (out, ok)
}

// Prefer human-scale linear breaks and 1/2/5 decades on log axes. Symlog
// retains equal transformed-space positions until a symmetric break policy exists.
fn nice_ticks(scale: Scale, lo: f32, hi: f32, wanted: usize, out: []Tick) -> ([]Tick, err) {
    if wanted < 2usize { ret (zero, Invalid) }
    if out.len < wanted { ret (zero, TooLarge) }
    if !valid_scale(scale, lo, hi) { ret (zero, Invalid) }
    if scale.kind == .Symlog {
        let (made, tick_error) = ticks(scale, lo, hi, out[..wanted])
        ret (made, tick_error)
    }
    var count = 0usize
    if scale.kind == .Linear {
        let raw = (f64(hi) - f64(lo)) / f64(wanted - 1usize)
        let unit = math.pow[f64](10.0f64, math.floor[f64](math.log10[f64](raw)))
        let ratio = raw / unit
        var factor = 10.0f64
        if ratio <= 1.0f64 {
            factor = 1.0f64
        } else if ratio <= 2.0f64 {
            factor = 2.0f64
        } else if ratio <= 5.0f64 {
            factor = 5.0f64
        }
        let step = factor * unit
        var value = math.ceil[f64](f64(lo) / step) * step
        var attempts = 0usize
        while value <= f64(hi) + step * 0.000000001f64 && attempts < wanted + 2usize {
            let rounded = f32(value)
            if count < wanted && rounded >= lo && rounded <= hi && (count == 0usize || rounded > out[count - 1usize].value) {
                var at = fraction(rounded, lo, hi, scale)
                if at < 0.0 { at = 0.0 }
                if at > 1.0 { at = 1.0 }
                out[count] = Tick { value: rounded, fraction: at }
                count += 1usize
            }
            value += step
            attempts += 1usize
        }
    } else {
        let multipliers = [3]f64{ 1.0f64, 2.0f64, 5.0f64 }
        var candidates: [256]f32 = zero
        var candidate_count = 0usize
        var exponent = math.floor[f64](math.log10[f64](f64(lo)))
        let last = math.ceil[f64](math.log10[f64](f64(hi)))
        while exponent <= last {
            let unit = math.pow[f64](10.0f64, exponent)
            var m = 0usize
            while m < multipliers.len {
                let raw = multipliers[m] * unit
                if raw >= f64(lo) && raw <= f64(hi) {
                    let rounded = f32(raw)
                    if rounded >= lo && rounded <= hi && (candidate_count == 0usize || rounded > candidates[candidate_count - 1usize]) {
                        if candidate_count >= candidates.len { ret (zero, TooLarge) }
                        candidates[candidate_count] = rounded
                        candidate_count += 1usize
                    }
                }
                m += 1usize
            }
            exponent += 1.0f64
        }
        if candidate_count >= 2usize {
            count = candidate_count
            if count > wanted { count = wanted }
            var i = 0usize
            while i < count {
                let index = (i * (candidate_count - 1usize) + (count - 1usize) / 2usize) / (count - 1usize)
                let value = candidates[index]
                var at = fraction(value, lo, hi, scale)
                if at < 0.0 { at = 0.0 }
                if at > 1.0 { at = 1.0 }
                out[i] = Tick { value: value, fraction: at }
                i += 1usize
            }
        }
    }
    if count < 2usize {
        let (fallback, fallback_error) = ticks(scale, lo, hi, out[..2usize])
        ret (fallback, fallback_error)
    }
    ret (out[..count], ok)
}

// Text slices point into caller-owned storage, which must outlive the labels.
fn format_ticks(values: []const Tick, out: []str, storage: []u8) -> ([]str, err) {
    if out.len < values.len { ret (zero, TooLarge) }
    var used = 0usize
    var i = 0usize
    while i < values.len {
        if !finite(values[i].value) { ret (zero, Invalid) }
        if used == storage.len { ret (zero, TooLarge) }
        var arena = mem.arena_from(storage[used..])
        let (made, builder_error) = str.builder(&arena, 0usize)
        if builder_error != ok { ret (zero, builder_error) }
        var builder = made
        var value = values[i].value
        if value == 0.0 { value = 0.0 }
        try str.push_f32(&builder, value)
        let label = str.done(&builder)
        out[i] = label
        used += label.len
        i += 1usize
    }
    ret (out[..values.len], ok)
}

fn valid_label(label: *const Label) -> bool {
    if label.text.len == 0usize || !finite(label.anchor.x) || !finite(label.anchor.y) { ret false }
    var i = 0usize
    while i < label.text.len {
        if label.text[i] < 32u8 || label.text[i] == 127u8 { ret false }
        i += 1usize
    }
    ret true
}

// Caller supplies text (and therefore formatting); this only positions it.
// Anchors are text baselines, not bounding-box corners.
fn guide_labels(bounds: geometry.Rect, x_ticks: []const Tick, x_text: []const str, y_ticks: []const Tick, y_text: []const str, size: f32, out: []Label) -> ([]Label, err) {
    if !valid_bounds(bounds) || !finite(size) || size <= 0.0 || x_ticks.len != x_text.len || y_ticks.len != y_text.len { ret (zero, Invalid) }
    if out.len < x_ticks.len || out.len - x_ticks.len < y_ticks.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < x_ticks.len {
        let position = x_ticks[i].fraction
        if !finite(position) || position < 0.0 || position > 1.0 { ret (zero, Invalid) }
        let label = Label { text: x_text[i], anchor: Coord { x: bounds.x + bounds.width * position, y: bounds.y + bounds.height + size + 6.0 }, align: .Center }
        if !valid_label(&label) { ret (zero, Invalid) }
        out[i] = label
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        let position = y_ticks[i].fraction
        if !finite(position) || position < 0.0 || position > 1.0 { ret (zero, Invalid) }
        let label = Label { text: y_text[i], anchor: Coord { x: bounds.x - 9.0, y: bounds.y + bounds.height * (1.0 - position) + size * 0.35 }, align: .Right }
        if !valid_label(&label) { ret (zero, Invalid) }
        out[x_ticks.len + i] = label
        i += 1usize
    }
    ret (out[..x_ticks.len + y_ticks.len], ok)
}

// Category centers use the same guide-label contract as numeric tick marks.
fn category_ticks(count: usize, out: []Tick) -> ([]Tick, err) {
    if count == 0usize { ret (zero, Empty) }
    if out.len < count { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        out[i] = Tick { value: f32(i), fraction: f32((f64(i) + 0.5f64) / f64(count)) }
        i += 1usize
    }
    ret (out[..count], ok)
}

// An explicit ordered factor axis. Repeated keys aggregate into their level;
// absent levels keep a zero-height slot and therefore retain their labels.
fn discrete_axis_bars(keys: []const str, values: []const f64, levels: []const str, domain_max: f64, bounds: geometry.Rect, sums: []f64, bars: []geometry.Rect, ticks_out: []Tick) -> (Layout, err) {
    if keys.len == 0usize || levels.len == 0usize { ret (zero, Empty) }
    if values.len != keys.len || !finite64(domain_max) || domain_max <= 0.0f64 || !valid_bounds(bounds) { ret (zero, Invalid) }
    let n = levels.len
    if sums.len < n || bars.len < n || ticks_out.len < n { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if levels[i].len == 0usize { ret (zero, Invalid) }
        var j = 0usize
        while j < i {
            if str.eq(levels[i], levels[j]) { ret (zero, Invalid) }
            j += 1usize
        }
        sums[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < keys.len {
        if !finite64(values[i]) || values[i] < 0.0f64 { ret (zero, Invalid) }
        var found = false
        var j = 0usize
        while j < n {
            if str.eq(keys[i], levels[j]) {
                sums[j] += values[i]
                if !finite64(sums[j]) || sums[j] > domain_max { ret (zero, Invalid) }
                found = true
                break
            }
            j += 1usize
        }
        if !found { ret (zero, Invalid) }
        i += 1usize
    }
    let (axis_ticks, tick_error) = category_ticks(n, ticks_out)
    if tick_error != ok { ret (zero, tick_error) }
    let slot = bounds.width / f32(n)
    if !finite(slot) || slot <= 0.0 { ret (zero, Invalid) }
    i = 0usize
    while i < n {
        let height = bounds.height * f32(sums[i] / domain_max)
        let width = slot * 0.68
        let x = bounds.x + slot * f32(i) + (slot - width) * 0.5
        let y = bounds.y + bounds.height - height
        if !finite(x + width) || !finite(y) || !finite(height) { ret (zero, Invalid) }
        bars[i] = geometry.rect(x, y, width, height)
        i += 1usize
    }
    ret (Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..n], x_min: 0.0, x_max: f32(n), y_min: 0.0, y_max: f32(domain_max) }, ok)
}

fn valid_chart_date(date: time.Date) -> bool {
    if date.year < 1i32 || date.year > 9999i32 || date.month < 1u8 || date.month > 12u8 { ret false }
    ret date.day >= 1u8 && i64(date.day) <= time.days_in_month(i64(date.year), i64(date.month))
}

// Month-start breaks preserve real calendar spacing, including leap days.
// The stride is measured in calendar months, not a fixed number of days.
fn date_ticks(start: time.Date, end: time.Date, month_stride: usize, out: []DateTick) -> ([]DateTick, err) {
    if !valid_chart_date(start) || !valid_chart_date(end) || month_stride == 0usize || month_stride > 120usize { ret (zero, Invalid) }
    let first_day = time.days_from_civil(i64(start.year), i64(start.month), i64(start.day))
    let last_day = time.days_from_civil(i64(end.year), i64(end.month), i64(end.day))
    if last_day <= first_day { ret (zero, Invalid) }
    var month = i64(start.year) * 12i64 + i64(start.month) - 1i64
    let last_month = i64(end.year) * 12i64 + i64(end.month) - 1i64
    if start.day > 1u8 { month += 1i64 }
    let stride = i64(month_stride)
    let remainder = month % stride
    if remainder != 0i64 { month += stride - remainder }
    var count = 0usize
    while month <= last_month {
        let year = month / 12i64
        let calendar_month = month % 12i64 + 1i64
        let day = time.days_from_civil(year, calendar_month, 1i64)
        if day <= last_day {
            if count == out.len { ret (zero, TooLarge) }
            out[count] = DateTick { date: time.Date { year: i32(year), month: u8(calendar_month), day: 1u8 }, fraction: f32(f64(day - first_day) / f64(last_day - first_day)) }
            count += 1usize
        }
        month += stride
    }
    ret (out[..count], ok)
}

// ISO year-month labels live in caller storage and remain valid while it does.
fn format_date_ticks(ticks_in: []const DateTick, out: []str, storage: []u8) -> ([]str, err) {
    if out.len < ticks_in.len { ret (zero, TooLarge) }
    var used = 0usize
    var i = 0usize
    while i < ticks_in.len {
        let date = ticks_in[i].date
        if !valid_chart_date(date) || date.day != 1u8 { ret (zero, Invalid) }
        if storage.len - used < 7usize { ret (zero, TooLarge) }
        var arena = mem.arena_from(storage[used..])
        let (made, builder_error) = str.builder(&arena, 0usize)
        if builder_error != ok { ret (zero, builder_error) }
        var builder = made
        if date.year < 10i32 {
            try str.push(&builder, "000")
        } else if date.year < 100i32 {
            try str.push(&builder, "00")
        } else if date.year < 1000i32 {
            try str.push(&builder, "0")
        }
        try str.push_i32(&builder, date.year)
        try str.push(&builder, "-")
        if date.month < 10u8 { try str.push(&builder, "0") }
        try str.push_i32(&builder, i32(date.month))
        let label = str.done(&builder)
        out[i] = label
        used += label.len
        i += 1usize
    }
    ret (out[..ticks_in.len], ok)
}

// Ordered civil dates map to elapsed days rather than equal category slots.
// Explicit date/y domains let several series share the same axes.
fn date_axis_line(dates: []const time.Date, values: []const f64, start: time.Date, end: time.Date, y_min: f64, y_max: f64, bounds: geometry.Rect, points: []Coord, segments: []Segment) -> (Layout, err) {
    let n = dates.len
    if n == 0usize { ret (zero, Empty) }
    if n < 2usize || values.len != n || !valid_chart_date(start) || !valid_chart_date(end) || !finite64(y_min) || !finite64(y_max) || y_max <= y_min || !valid_bounds(bounds) { ret (zero, Invalid) }
    let first_day = time.days_from_civil(i64(start.year), i64(start.month), i64(start.day))
    let last_day = time.days_from_civil(i64(end.year), i64(end.month), i64(end.day))
    if last_day <= first_day { ret (zero, Invalid) }
    if points.len < n || segments.len < n - 1usize { ret (zero, TooLarge) }
    var previous = first_day - 1i64
    var i = 0usize
    while i < n {
        if !valid_chart_date(dates[i]) || !finite64(values[i]) || values[i] < y_min || values[i] > y_max { ret (zero, Invalid) }
        let day = time.days_from_civil(i64(dates[i].year), i64(dates[i].month), i64(dates[i].day))
        if day <= previous || day < first_day || day > last_day { ret (zero, Invalid) }
        let x = bounds.x + bounds.width * f32(f64(day - first_day) / f64(last_day - first_day))
        let y = bounds.y + bounds.height * (1.0 - f32((values[i] - y_min) / (y_max - y_min)))
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        if i > 0usize { segments[i - 1usize] = Segment { from: points[i - 1usize], to: points[i] } }
        previous = day
        i += 1usize
    }
    ret (Layout { kind: .PointLine, coords: points[..n], segments: segments[..n - 1usize], bars: zero, x_min: f32(first_day), x_max: f32(last_day), y_min: f32(y_min), y_max: f32(y_max) }, ok)
}

// Palette stays with the caller; each swatch and label shares its series index.
fn legend_items(names: []const str, origin: Coord, swatch: f32, row_height: f32, out: []LegendItem) -> ([]LegendItem, err) {
    if !finite(origin.x) || !finite(origin.y) || !finite(swatch) || !finite(row_height) || swatch <= 0.0 || row_height < swatch { ret (zero, Invalid) }
    if out.len < names.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < names.len {
        let y = origin.y + f32(i) * row_height
        let label = Label { text: names[i], anchor: Coord { x: origin.x + swatch + 6.0, y: y + swatch }, align: .Left }
        if !finite(y) || !valid_label(&label) { ret (zero, Invalid) }
        out[i] = LegendItem { swatch: geometry.rect(origin.x, y, swatch, swatch), label: label }
        i += 1usize
    }
    ret (out[..names.len], ok)
}

// Equal-interval classes for a choropleth's colours (D2115): the class of a
// region's place `t` in the range, a `fraction` from 0 to 1; 0 for the lowest, the
// maximum in the top class.
fn class_of(t: f32, classes: usize) -> usize {
    if classes == 0usize || !(t > 0.0) { ret 0usize }
    let c = usize(t * f32(classes))
    if c >= classes { ret classes - 1usize }
    ret c
}

// `classes` swatches left to right across `bounds`, swatch i holding `class_of`'s
// class i, and the `classes + 1` breaks between and around them as ticks (the
// value, and the fraction along the strip) for `format_ticks` to write.
fn class_legend(minimum: f64, maximum: f64, classes: usize, bounds: geometry.Rect, swatches: []geometry.Rect, breaks: []Tick) -> (ClassLegend, err) {
    if classes == 0usize || !finite64(minimum) || !finite64(maximum) || maximum < minimum || !finite(f32(minimum)) || !finite(f32(maximum)) || !valid_bounds(bounds) { ret (zero, Invalid) }
    if swatches.len < classes || breaks.len < classes + 1usize { ret (zero, TooLarge) }
    let width = bounds.width / f32(classes)
    var i = 0usize
    while i <= classes {
        let t = f64(i) / f64(classes)
        breaks[i] = Tick { value: f32(minimum + (maximum - minimum) * t), fraction: f32(t) }
        if i < classes { swatches[i] = geometry.rect(bounds.x + width * f32(i), bounds.y, width, bounds.height) }
        i += 1usize
    }
    ret (ClassLegend { swatches: swatches[..classes], breaks: breaks[..classes + 1usize] }, ok)
}

// Text widths are measured by the caller's chosen font/size. Wrapping only
// happens between complete items, so swatches and labels cannot split.
fn wrapped_legend_items(names: []const str, text_widths: []const f32, bounds: geometry.Rect, swatch: f32, gap: f32, row_height: f32, out: []LegendItem) -> (WrappedLegend, err) {
    if names.len == 0usize { ret (zero, Empty) }
    if names.len != text_widths.len || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(swatch) || !finite(gap) || !finite(row_height) || swatch <= 0.0 || gap < 0.0 || row_height < swatch { ret (zero, Invalid) }
    if out.len < names.len { ret (zero, TooLarge) }
    var row = 0usize
    var cursor = bounds.x
    var i = 0usize
    while i < names.len {
        let width = text_widths[i]
        if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
        let item_width = swatch + 5.0 + width
        if !finite(item_width) || item_width > bounds.width { ret (zero, TooLarge) }
        if cursor > bounds.x && cursor + item_width > bounds.x + bounds.width {
            row += 1usize
            cursor = bounds.x
        }
        if f32(row + 1usize) * row_height > bounds.height { ret (zero, TooLarge) }
        let y = bounds.y + f32(row) * row_height + (row_height - swatch) * 0.5
        let label = Label { text: names[i], anchor: Coord { x: cursor + swatch + 5.0, y: y + swatch }, align: .Left }
        if !valid_label(&label) || !finite(cursor + item_width) || !finite(y + swatch) { ret (zero, Invalid) }
        out[i] = LegendItem { swatch: geometry.rect(cursor, y, swatch, swatch), label: label }
        cursor += item_width + gap
        i += 1usize
    }
    ret (WrappedLegend { items: out[..names.len], rows: row + 1usize }, ok)
}

fn boxes_overlap(a: geometry.Rect, b: geometry.Rect) -> bool {
    ret a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
}

// Point labels without collisions: each label, in the caller's priority order,
// takes the first of eight candidate boxes around its point (Imhof's order:
// upper-right, upper-left, lower-right, lower-left, right, left, above, below)
// that stays inside `bounds`, overlaps no label placed before it and keeps
// `clearance` from every other point (`offset` spaces it from its own). A label with no free slot is returned with
// `placed` false rather than drawn over the data. `widths` are measured text
// widths; `baseline` is the distance from a box's top to the text baseline.
// ponytail: greedy, O(n^2) per label; simulated annealing or a conflict graph
// places more labels in dense clusters if that ever matters.
fn place_point_labels(points: []const Coord, texts: []const str, widths: []const f32, height: f32, baseline: f32, bounds: geometry.Rect, offset: f32, clearance: f32, out: []LabelPlacement) -> (PointLabels, err) {
    if points.len == 0usize { ret (zero, Empty) }
    if texts.len != points.len || widths.len != points.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if !finite(height) || height <= 0.0 || !finite(baseline) || baseline < 0.0 || baseline > height || !finite(offset) || offset < 0.0 || !finite(clearance) || clearance < 0.0 { ret (zero, Invalid) }
    if out.len < points.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < points.len {
        if !finite(points[i].x) || !finite(points[i].y) || !finite(widths[i]) || widths[i] <= 0.0 || texts[i].len == 0usize || !text_layout.valid_utf8(texts[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var placed_count = 0usize
    i = 0usize
    while i < points.len {
        let p = points[i]
        let w = widths[i]
        let xs = [8]f32{ p.x + offset, p.x - offset - w, p.x + offset, p.x - offset - w, p.x + offset, p.x - offset - w, p.x - w / 2.0, p.x - w / 2.0 }
        let ys = [8]f32{ p.y - offset - height, p.y - offset - height, p.y + offset, p.y + offset, p.y - height / 2.0, p.y - height / 2.0, p.y - offset - height, p.y + offset }
        out[i] = LabelPlacement { label: Label { text: texts[i], anchor: p, align: .Left }, box: zero, placed: false, slot: 0u8 }
        var slot = 0usize
        while slot < 8usize {
            let box = geometry.rect(xs[slot], ys[slot], w, height)
            var free = box.x >= bounds.x && box.y >= bounds.y && box.x + box.width <= bounds.x + bounds.width && box.y + box.height <= bounds.y + bounds.height
            var j = 0usize
            while free && j < i {
                if out[j].placed && boxes_overlap(box, out[j].box) { free = false }
                j += 1usize
            }
            let padded = geometry.rect(box.x - clearance, box.y - clearance, box.width + 2.0 * clearance, box.height + 2.0 * clearance)
            j = 0usize
            while free && j < points.len {
                if j != i && points[j].x > padded.x && points[j].x < padded.x + padded.width && points[j].y > padded.y && points[j].y < padded.y + padded.height { free = false }
                j += 1usize
            }
            if free {
                out[i] = LabelPlacement { label: Label { text: texts[i], anchor: Coord { x: box.x, y: box.y + baseline }, align: .Left }, box: box, placed: true, slot: u8(slot) }
                placed_count += 1usize
                slot = 8usize
            } else {
                slot += 1usize
            }
        }
        i += 1usize
    }
    ret (PointLabels { labels: out[..points.len], placed: placed_count }, ok)
}

// Produces marks in screen coordinates. Y is inverted because graphics bounds
// use a top-left origin; the returned domain remains in data coordinates.
fn layout(s: *const Spec, coords: []Coord, segments: []Segment, bars: []geometry.Rect) -> (Layout, err) {
    let (marks, marks_error) = layout_with_limits(s, coords, segments, bars, s.x[..0usize], s.y[..0usize])
    ret (marks, marks_error)
}

// Observation order, rather than sorted x order, defines the connecting path.
fn connected_scatter(x: []const f32, y: []const f32, bounds: geometry.Rect, points: []Coord, segments: []Segment) -> (Layout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len < 2usize || x.len != y.len { ret (zero, Invalid) }
    let series = spec(.PointLine, bounds, x, y)
    let (marks, marks_error) = layout(&series, points, segments, zero)
    ret (marks, marks_error)
}

// Presence is separate from numeric payload: a missing x or y omits the row,
// while an observed non-finite or out-of-domain value is an error. Row IDs
// remain aligned with compacted marks for later hit-testing and selection.
fn masked_scatter(x: []const f32, y: []const f32, x_present: []const bool, y_present: []const bool, bounds: geometry.Rect, x_min: f32, x_max: f32, y_min: f32, y_max: f32, points: []Coord, row_ids: []usize) -> (MaskedScatterLayout, err) {
    let n = x.len
    if n == 0usize { ret (zero, Empty) }
    if y.len != n || x_present.len != n || y_present.len != n || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(x_min) || !finite(x_max) || !finite(y_min) || !finite(y_max) || x_max <= x_min || y_max <= y_min || !finite(x_max - x_min) || !finite(y_max - y_min) { ret (zero, Invalid) }
    var complete = 0usize
    var i = 0usize
    while i < n {
        if x_present[i] && y_present[i] {
            if !finite(x[i]) || !finite(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
            complete += 1usize
        }
        i += 1usize
    }
    if points.len < complete || row_ids.len < complete { ret (zero, TooLarge) }
    var used = 0usize
    i = 0usize
    while i < n {
        if x_present[i] && y_present[i] {
            let px = bounds.x + bounds.width * ((x[i] - x_min) / (x_max - x_min))
            let py = bounds.y + bounds.height * (1.0 - (y[i] - y_min) / (y_max - y_min))
            if !finite(px) || !finite(py) { ret (zero, Invalid) }
            points[used] = Coord { x: px, y: py }
            row_ids[used] = i
            used += 1usize
        }
        i += 1usize
    }
    let marks = Layout { kind: .Scatter, coords: points[..used], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }
    ret (MaskedScatterLayout { marks: marks, row_ids: row_ids[..used], omitted: n - used }, ok)
}

// Pick the nearest rendered scatter mark within a screen-space radius.
// Optional row IDs preserve identity after missing-data compaction; equal-
// distance ties choose the earlier displayed mark deterministically.
fn hit_scatter(marks: *const Layout, row_ids: []const usize, pointer: Coord, radius: f32) -> (SelectionHit, bool, err) {
    if marks.kind != .Scatter || (row_ids.len != 0usize && row_ids.len != marks.coords.len) || !finite(pointer.x) || !finite(pointer.y) || !finite(radius) || radius < 0.0 { ret (zero, false, Invalid) }
    let limit = f64(radius) * f64(radius)
    var found = false
    var best: SelectionHit = zero
    var i = 0usize
    while i < marks.coords.len {
        let point = marks.coords[i]
        if !finite(point.x) || !finite(point.y) { ret (zero, false, Invalid) }
        let dx = f64(pointer.x) - f64(point.x)
        let dy = f64(pointer.y) - f64(point.y)
        let distance_squared = dx * dx + dy * dy
        if distance_squared <= limit && (!found || distance_squared < best.distance_squared) {
            var source_row = i
            if row_ids.len > 0usize { source_row = row_ids[i] }
            best = SelectionHit { mark_index: i, source_row: source_row, distance_squared: distance_squared }
            found = true
        }
        i += 1usize
    }
    ret (best, found, ok)
}

// A Box layout makes the same selected-point outline usable by scene and SVG.
fn selected_point_outline(marks: *const Layout, mark_index: usize, padding: f32, storage: []geometry.Rect) -> (Layout, err) {
    if marks.kind != .Scatter || mark_index >= marks.coords.len || !finite(padding) || padding < 0.0 { ret (zero, Invalid) }
    if storage.len < 1usize { ret (zero, TooLarge) }
    let point = marks.coords[mark_index]
    let half_side = 3.0 + padding
    let side = half_side * 2.0
    if !finite(point.x) || !finite(point.y) || !finite(side) || !finite(point.x - half_side) || !finite(point.y - half_side) || !finite(point.x + half_side) || !finite(point.y + half_side) { ret (zero, Invalid) }
    storage[0usize] = geometry.rect(point.x - half_side, point.y - half_side, side, side)
    let outline = Layout { kind: .Box, coords: zero, segments: zero, bars: storage[..1usize], x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
    ret (outline, ok)
}

// Tenor is measured in years and yield in the caller's consistent rate unit
// (for example percent). Explicit domains let several dated curves share axes;
// the layout connects supplied observations without fitting or extrapolation.
fn yield_curve(tenors: []const f64, yields: []const f64, tenor_max: f64, yield_min: f64, yield_max: f64, bounds: geometry.Rect, points: []Coord, segments: []Segment) -> (Layout, err) {
    let n = tenors.len
    if n == 0usize { ret (zero, Empty) }
    if n < 2usize || yields.len != n || !finite64(tenor_max) || tenor_max <= 0.0f64 || !finite64(yield_min) || !finite64(yield_max) || yield_max <= yield_min || !finite64(yield_max - yield_min) || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if !finite(f32(tenor_max)) || !finite(f32(yield_min)) || !finite(f32(yield_max)) || f32(yield_min) == f32(yield_max) { ret (zero, Invalid) }
    if points.len < n || segments.len < n - 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        let tenor = tenors[i]
        let rate = yields[i]
        if !finite64(tenor) || tenor <= 0.0f64 || tenor > tenor_max || (i > 0usize && tenor <= tenors[i - 1usize]) || !finite64(rate) || rate < yield_min || rate > yield_max { ret (zero, Invalid) }
        let x = bounds.x + bounds.width * f32(tenor / tenor_max)
        let y = bounds.y + bounds.height * (1.0f32 - f32((rate - yield_min) / (yield_max - yield_min)))
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        if i > 0usize { segments[i - 1usize] = Segment { from: points[i - 1usize], to: points[i] } }
        i += 1usize
    }
    ret (Layout { kind: .PointLine, coords: points[..n], segments: segments[..n - 1usize], bars: zero, x_min: 0.0f32, x_max: f32(tenor_max), y_min: f32(yield_min), y_max: f32(yield_max) }, ok)
}

// Right-facing Ishikawa diagram. A cause's parent is -1 for a direct category
// cause, or an earlier cause index in the same category for a deeper subcause.
// Input order is stable and defines sibling order; output never owns the text.
fn fishbone(effect: str, categories: []const str, causes: []const FishboneCause, bounds: geometry.Rect, spine: []Segment, ribs: []Segment, branches: []Segment, head_box: []geometry.Rect, labels: []Label) -> (FishboneLayout, err) {
    if categories.len == 0usize || !valid_bounds(bounds) || causes.len > 2147483647usize { ret (zero, Invalid) }
    if spine.len < 3usize || ribs.len < categories.len || branches.len < causes.len || head_box.len < 1usize || labels.len < 1usize + categories.len || labels.len - 1usize - categories.len < causes.len { ret (zero, TooLarge) }
    let center_y = bounds.y + bounds.height * 0.5
    let spine_start = bounds.x + bounds.width * 0.05
    let spine_end = bounds.x + bounds.width * 0.81
    let head_left = bounds.x + bounds.width * 0.83
    let head_width = bounds.width * 0.16
    let rib_height = bounds.height * 0.31
    let head_height = bounds.height * 0.23
    if !finite(center_y) || !finite(spine_start) || !finite(spine_end) || !finite(head_left) || !finite(head_width) || !finite(rib_height) || !finite(head_height) { ret (zero, Invalid) }
    let effect_label = Label { text: effect, anchor: Coord { x: head_left + head_width * 0.5, y: center_y + 3.0 }, align: .Center }
    if !valid_label(&effect_label) { ret (zero, Invalid) }
    labels[0usize] = effect_label
    var i = 0usize
    while i < categories.len {
        let held_label = Label { text: categories[i], anchor: Coord { x: spine_start, y: center_y }, align: .Center }
        if !valid_label(&held_label) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < causes.len {
        let cause = causes[i]
        if cause.category >= categories.len || cause.parent < -1i32 || cause.parent >= i32(i) { ret (zero, Invalid) }
        if cause.parent >= 0i32 && causes[usize(cause.parent)].category != cause.category { ret (zero, Invalid) }
        let held_label = Label { text: cause.text, anchor: Coord { x: spine_start, y: center_y }, align: .Left }
        if !valid_label(&held_label) { ret (zero, Invalid) }
        i += 1usize
    }
    let stations = (categories.len + 1usize) / 2usize
    let station_width = (spine_end - spine_start) / f32(stations + 1usize)
    spine[0usize] = Segment { from: Coord { x: spine_start, y: center_y }, to: Coord { x: spine_end, y: center_y } }
    spine[1usize] = Segment { from: Coord { x: spine_end - 9.0, y: center_y - 5.0 }, to: Coord { x: spine_end, y: center_y } }
    spine[2usize] = Segment { from: Coord { x: spine_end - 9.0, y: center_y + 5.0 }, to: Coord { x: spine_end, y: center_y } }
    head_box[0usize] = geometry.rect(head_left, center_y - head_height * 0.5, head_width, head_height)
    i = 0usize
    while i < categories.len {
        var side = -1.0f32
        if i % 2usize == 1usize { side = 1.0 }
        let root_x = spine_start + station_width * f32(i / 2usize + 1usize)
        let tip = Coord { x: root_x - station_width * 0.31, y: center_y + side * rib_height }
        ribs[i] = Segment { from: Coord { x: root_x, y: center_y }, to: tip }
        labels[1usize + i] = Label { text: categories[i], anchor: Coord { x: tip.x, y: tip.y + side * 7.0 }, align: .Center }
        i += 1usize
    }
    i = 0usize
    while i < causes.len {
        let cause = causes[i]
        var source = ribs[cause.category]
        var depth = 0usize
        if cause.parent >= 0i32 {
            source = branches[usize(cause.parent)]
            var parent = cause.parent
            while parent >= 0i32 {
                depth += 1usize
                parent = causes[usize(parent)].parent
            }
        }
        var total = 0usize
        var rank = 0usize
        var j = 0usize
        while j < causes.len {
            if causes[j].category == cause.category && causes[j].parent == cause.parent {
                if j < i { rank += 1usize }
                total += 1usize
            }
            j += 1usize
        }
        let portion = f32(rank + 1usize) / f32(total + 1usize)
        let anchor = Coord { x: source.from.x + (source.to.x - source.from.x) * portion, y: source.from.y + (source.to.y - source.from.y) * portion }
        var scale = 1.0f32
        j = 0usize
        while j < depth {
            scale *= 0.5
            j += 1usize
        }
        var side = -1.0f32
        if cause.category % 2usize == 1usize { side = 1.0 }
        let tip = Coord { x: anchor.x + station_width * 0.30 * scale, y: anchor.y + side * rib_height * 0.17 * scale }
        if !finite(tip.x) || !finite(tip.y) { ret (zero, Invalid) }
        branches[i] = Segment { from: anchor, to: tip }
        labels[1usize + categories.len + i] = Label { text: cause.text, anchor: Coord { x: tip.x + 3.0, y: tip.y + side * 3.0 }, align: .Left }
        i += 1usize
    }
    let spine_layout = Layout { kind: .Rug, coords: zero, segments: spine[..3usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let rib_layout = Layout { kind: .Rug, coords: zero, segments: ribs[..categories.len], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let cause_layout = Layout { kind: .Rug, coords: zero, segments: branches[..causes.len], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let head_layout = Layout { kind: .Bar, coords: zero, segments: zero, bars: head_box[..1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret (FishboneLayout { spine: spine_layout, ribs: rib_layout, causes: cause_layout, head: head_layout, labels: labels[..1usize + categories.len + causes.len] }, ok)
}

// Effect at index zero, with each later cause naming an earlier parent.
// Subtree widths are leaf-proportional; sibling order follows node input order.
fn cause_effect_tree(nodes: []const CauseTreeNode, bounds: geometry.Rect, work: *CauseTreeWork, boxes: []geometry.Rect, connectors: []Segment, labels: []Label) -> (CauseTreeLayout, err) {
    let n = nodes.len
    if n == 0usize { ret (zero, Empty) }
    if n > 2147483647usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if work.placements.len < n || work.cursor.len < n || boxes.len < n || labels.len < n || connectors.len / 3usize < n - 1usize { ret (zero, TooLarge) }
    if nodes[0usize].parent != -1i32 { ret (zero, Invalid) }
    var i = 0usize
    while i < n {
        if i > 0usize && (nodes[i].parent < 0i32 || nodes[i].parent >= i32(i)) { ret (zero, Invalid) }
        let probe = Label { text: nodes[i].text, anchor: Coord { x: bounds.x, y: bounds.y }, align: .Center }
        if !valid_label(&probe) { ret (zero, Invalid) }
        work.placements[i] = CauseTreePlacement { depth: 0usize, leaf_start: 0usize, leaf_count: 1usize, children: 0usize }
        work.cursor[i] = 0usize
        i += 1usize
    }
    var levels = 1usize
    i = 1usize
    while i < n {
        let parent = usize(nodes[i].parent)
        work.placements[i].depth = work.placements[parent].depth + 1usize
        if work.placements[i].depth + 1usize > levels { levels = work.placements[i].depth + 1usize }
        i += 1usize
    }
    i = n
    while i > 1usize {
        i -= 1usize
        let parent = usize(nodes[i].parent)
        if work.placements[parent].children == 0usize { work.placements[parent].leaf_count = 0usize }
        work.placements[parent].children += 1usize
        work.placements[parent].leaf_count += work.placements[i].leaf_count
    }
    let leaves = work.placements[0usize].leaf_count
    i = 1usize
    while i < n {
        let parent = usize(nodes[i].parent)
        work.placements[i].leaf_start = work.placements[parent].leaf_start + work.cursor[parent]
        work.cursor[parent] += work.placements[i].leaf_count
        i += 1usize
    }
    let column_width = bounds.width / f32(levels)
    let leaf_height = bounds.height / f32(leaves)
    var box_width = column_width * 0.72
    if box_width > 116.0 { box_width = 116.0 }
    var box_height = leaf_height * 0.60
    if box_height > 34.0 { box_height = 34.0 }
    if !finite(column_width) || !finite(leaf_height) || column_width < 55.0 || leaf_height < 23.0 || !finite(box_width) || !finite(box_height) { ret (zero, TooLarge) }
    i = 0usize
    while i < n {
        let place = work.placements[i]
        let center_x = bounds.x + bounds.width - (f32(place.depth) + 0.5) * column_width
        let center_y = bounds.y + (f32(place.leaf_start) + f32(place.leaf_count) * 0.5) * leaf_height
        let left = center_x - box_width * 0.5
        let top = center_y - box_height * 0.5
        if !finite(left) || !finite(top) || !finite(left + box_width) || !finite(top + box_height) { ret (zero, Invalid) }
        boxes[i] = geometry.rect(left, top, box_width, box_height)
        labels[i] = Label { text: nodes[i].text, anchor: Coord { x: center_x, y: center_y + 3.0 }, align: .Center }
        i += 1usize
    }
    i = 1usize
    while i < n {
        let from = boxes[usize(nodes[i].parent)]
        let to = boxes[i]
        let x0 = from.x
        let x1 = to.x + to.width
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let bend = (x0 + x1) * 0.5
        if !finite(bend) || !(x0 > x1) { ret (zero, Invalid) }
        let first = (i - 1usize) * 3usize
        connectors[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: bend, y: y0 } }
        connectors[first + 1usize] = Segment { from: Coord { x: bend, y: y0 }, to: Coord { x: bend, y: y1 } }
        connectors[first + 2usize] = Segment { from: Coord { x: bend, y: y1 }, to: Coord { x: x1, y: y1 } }
        i += 1usize
    }
    let node_layout = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..n], x_min: 0.0, x_max: f32(levels), y_min: 0.0, y_max: f32(leaves) }
    let link_layout = Layout { kind: .Rug, coords: zero, segments: connectors[..(n - 1usize) * 3usize], bars: zero, x_min: 0.0, x_max: f32(levels), y_min: 0.0, y_max: f32(leaves) }
    ret (CauseTreeLayout { nodes: node_layout, connectors: link_layout, labels: labels[..n], levels: levels, leaves: leaves }, ok)
}

// Six-panel normal capability report for individuals (subgroup size one).
// The caller supplies a sorted copy of values for the Q-Q panel and every
// output slice. Panel order: I, MR, last 25, histogram, Q-Q, capability.
fn capability_sixpack(values: []const f64, sorted: []const f64, lsl: f64, usl: f64, panels: []const geometry.Rect, work: *CapabilitySixpackStorage) -> (CapabilitySixpackLayout, err) {
    let n = values.len
    if n < 5usize || sorted.len != n || panels.len != 6usize { ret (zero, Invalid) }
    var p = 0usize
    while p < 6usize {
        if !valid_bounds(panels[p]) { ret (zero, Invalid) }
        p += 1usize
    }
    var recent_count = n
    if recent_count > 25usize { recent_count = 25usize }
    if work.moving.len < n - 1usize || work.individual_points.len < n || work.individual_lines.len < n - 1usize || work.range_points.len < n - 1usize || work.range_lines.len < n - 2usize || work.recent_points.len < recent_count || work.histogram_counts.len < 2usize || work.histogram_counts.len != work.histogram_bars.len || work.within_curve.len < 31usize || work.overall_curve.len < 31usize || work.probability_points.len < n || work.probability_reference.len < 1usize || work.interval_bars.len < 3usize || work.guides.len < 11usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if !finite64(sorted[i]) || (i > 0usize && sorted[i] < sorted[i - 1usize]) || !finite64(values[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    let (summary, summary_error) = stat.normal_capability_individuals(values, lsl, usl, work.moving)
    if summary_error != ok { ret (zero, Invalid) }
    let vmin = f32(sorted[0usize])
    let vmax = f32(sorted[n - 1usize])
    if !finite(vmin) || !finite(vmax) || vmin >= vmax { ret (zero, Invalid) }
    let mean = f32(summary.mean)
    let i_lo = f32(math.min[f64](sorted[0usize], summary.individuals.lower))
    let i_hi = f32(math.max[f64](sorted[n - 1usize], summary.individuals.upper))
    if !finite(i_lo) || !finite(i_hi) || !(i_hi > i_lo) { ret (zero, Invalid) }
    let i_rect = panels[0usize]
    i = 0usize
    while i < n {
        work.individual_points[i] = Coord { x: i_rect.x + i_rect.width * f32(i) / f32(n - 1usize), y: i_rect.y + i_rect.height * (1.0 - (f32(values[i]) - i_lo) / (i_hi - i_lo)) }
        if i > 0usize { work.individual_lines[i - 1usize] = Segment { from: work.individual_points[i - 1usize], to: work.individual_points[i] } }
        i += 1usize
    }
    let individuals = Layout { kind: .PointLine, coords: work.individual_points[..n], segments: work.individual_lines[..n - 1usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: i_lo, y_max: i_hi }
    let mr_rect = panels[1usize]
    var mr_hi = f32(summary.moving_range.upper)
    i = 0usize
    while i < n - 1usize {
        if f32(work.moving[i]) > mr_hi { mr_hi = f32(work.moving[i]) }
        i += 1usize
    }
    if !finite(mr_hi) || !(mr_hi > 0.0) { ret (zero, Invalid) }
    mr_hi *= 1.08
    i = 0usize
    while i < n - 1usize {
        work.range_points[i] = Coord { x: mr_rect.x + mr_rect.width * f32(i) / f32(n - 2usize), y: mr_rect.y + mr_rect.height * (1.0 - f32(work.moving[i]) / mr_hi) }
        if i > 0usize { work.range_lines[i - 1usize] = Segment { from: work.range_points[i - 1usize], to: work.range_points[i] } }
        i += 1usize
    }
    let moving_range = Layout { kind: .PointLine, coords: work.range_points[..n - 1usize], segments: work.range_lines[..n - 2usize], bars: zero, x_min: 2.0, x_max: f32(n), y_min: 0.0, y_max: mr_hi }
    let recent_rect = panels[2usize]
    let recent_lo = n - recent_count
    i = 0usize
    while i < recent_count {
        work.recent_points[i] = Coord { x: recent_rect.x + recent_rect.width * f32(i) / f32(recent_count - 1usize), y: recent_rect.y + recent_rect.height * (1.0 - (f32(values[recent_lo + i]) - vmin) / (vmax - vmin)) }
        i += 1usize
    }
    let recent = Layout { kind: .Scatter, coords: work.recent_points[..recent_count], segments: zero, bars: zero, x_min: f32(recent_lo + 1usize), x_max: f32(n), y_min: vmin, y_max: vmax }
    let hist_rect = panels[3usize]
    let wider = math.max[f64](summary.within_sigma, summary.overall_sigma)
    let hist_lo = math.min[f64](lsl, math.min[f64](sorted[0usize], summary.mean - 3.5f64 * wider))
    let hist_hi = math.max[f64](usl, math.max[f64](sorted[n - 1usize], summary.mean + 3.5f64 * wider))
    if !finite(f32(hist_lo)) || !finite(f32(hist_hi)) || !(hist_hi > hist_lo) { ret (zero, Invalid) }
    let bins = work.histogram_counts.len
    i = 0usize
    while i < bins {
        work.histogram_counts[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var bin = usize((values[i] - hist_lo) / (hist_hi - hist_lo) * f64(bins))
        if bin >= bins { bin = bins - 1usize }
        work.histogram_counts[bin] += 1u64
        i += 1usize
    }
    let bin_width = (hist_hi - hist_lo) / f64(bins)
    var peak = 0.0f64
    i = 0usize
    while i < bins {
        if f64(work.histogram_counts[i]) > peak { peak = f64(work.histogram_counts[i]) }
        i += 1usize
    }
    let pi = 3.14159265358979323846f64
    let within_peak = f64(n) * bin_width / (summary.within_sigma * math.sqrt[f64](2.0f64 * pi))
    let overall_peak = f64(n) * bin_width / (summary.overall_sigma * math.sqrt[f64](2.0f64 * pi))
    if within_peak > peak { peak = within_peak }
    if overall_peak > peak { peak = overall_peak }
    if !(peak > 0.0f64) || !finite(f32(peak)) { ret (zero, Invalid) }
    peak *= 1.08f64
    i = 0usize
    while i < bins {
        let height = hist_rect.height * f32(f64(work.histogram_counts[i]) / peak)
        work.histogram_bars[i] = geometry.rect(hist_rect.x + hist_rect.width * f32(i) / f32(bins), hist_rect.y + hist_rect.height - height, hist_rect.width / f32(bins), height)
        i += 1usize
    }
    let hist_layout = Layout { kind: .Histogram, coords: zero, segments: zero, bars: work.histogram_bars[..bins], x_min: f32(hist_lo), x_max: f32(hist_hi), y_min: 0.0, y_max: f32(peak) }
    var previous_within: Coord = zero
    var previous_overall: Coord = zero
    i = 0usize
    while i < 32usize {
        let x = hist_lo + (hist_hi - hist_lo) * f64(i) / 31.0f64
        let within_z = (x - summary.mean) / summary.within_sigma
        let overall_z = (x - summary.mean) / summary.overall_sigma
        let within_y = f64(n) * bin_width * math.exp[f64](-0.5f64 * within_z * within_z) / (summary.within_sigma * math.sqrt[f64](2.0f64 * pi))
        let overall_y = f64(n) * bin_width * math.exp[f64](-0.5f64 * overall_z * overall_z) / (summary.overall_sigma * math.sqrt[f64](2.0f64 * pi))
        let screen_x = hist_rect.x + hist_rect.width * f32(i) / 31.0
        let within_point = Coord { x: screen_x, y: hist_rect.y + hist_rect.height * (1.0 - f32(within_y / peak)) }
        let overall_point = Coord { x: screen_x, y: hist_rect.y + hist_rect.height * (1.0 - f32(overall_y / peak)) }
        if i > 0usize {
            work.within_curve[i - 1usize] = Segment { from: previous_within, to: within_point }
            work.overall_curve[i - 1usize] = Segment { from: previous_overall, to: overall_point }
        }
        previous_within = within_point
        previous_overall = overall_point
        i += 1usize
    }
    let within_curve = Layout { kind: .Line, coords: zero, segments: work.within_curve[..31usize], bars: zero, x_min: hist_layout.x_min, x_max: hist_layout.x_max, y_min: 0.0, y_max: hist_layout.y_max }
    let overall_curve = Layout { kind: .Line, coords: zero, segments: work.overall_curve[..31usize], bars: zero, x_min: hist_layout.x_min, x_max: hist_layout.x_max, y_min: 0.0, y_max: hist_layout.y_max }
    let (probability, qq_error) = qq_normal(sorted, panels[4usize], work.probability_points, work.probability_reference)
    if qq_error != ok { ret (zero, qq_error) }
    let cap_rect = panels[5usize]
    let cap_lo = hist_lo
    let cap_hi = hist_hi
    let spreads = [3]f64{ summary.within_sigma, summary.overall_sigma, 0.0f64 }
    i = 0usize
    while i < 3usize {
        var low = summary.mean - 3.0f64 * spreads[i]
        var high = summary.mean + 3.0f64 * spreads[i]
        if i == 2usize {
            low = lsl
            high = usl
        }
        let left = cap_rect.x + cap_rect.width * f32((low - cap_lo) / (cap_hi - cap_lo))
        let right = cap_rect.x + cap_rect.width * f32((high - cap_lo) / (cap_hi - cap_lo))
        work.interval_bars[i] = geometry.rect(left, cap_rect.y + f32(i) * cap_rect.height / 3.0 + 8.0, right - left, 9.0)
        var center = summary.mean
        if i == 2usize { center = (lsl + usl) * 0.5f64 }
        let center_x = cap_rect.x + cap_rect.width * f32((center - cap_lo) / (cap_hi - cap_lo))
        let bar_y = work.interval_bars[i].y
        work.guides[8usize + i] = Segment { from: Coord { x: center_x, y: bar_y - 3.0 }, to: Coord { x: center_x, y: bar_y + 12.0 } }
        i += 1usize
    }
    let intervals = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.interval_bars[..3usize], x_min: f32(cap_lo), x_max: f32(cap_hi), y_min: 0.0, y_max: 3.0 }
    let i_levels = [3]f64{ summary.individuals.lower, summary.mean, summary.individuals.upper }
    i = 0usize
    while i < 3usize {
        let y = i_rect.y + i_rect.height * (1.0 - (f32(i_levels[i]) - i_lo) / (i_hi - i_lo))
        work.guides[i] = Segment { from: Coord { x: i_rect.x, y: y }, to: Coord { x: i_rect.x + i_rect.width, y: y } }
        i += 1usize
    }
    let mr_levels = [2]f64{ summary.moving_range.center, summary.moving_range.upper }
    i = 0usize
    while i < 2usize {
        let y = mr_rect.y + mr_rect.height * (1.0 - f32(mr_levels[i]) / mr_hi)
        work.guides[3usize + i] = Segment { from: Coord { x: mr_rect.x, y: y }, to: Coord { x: mr_rect.x + mr_rect.width, y: y } }
        i += 1usize
    }
    let recent_y = recent_rect.y + recent_rect.height * (1.0 - (mean - vmin) / (vmax - vmin))
    work.guides[5usize] = Segment { from: Coord { x: recent_rect.x, y: recent_y }, to: Coord { x: recent_rect.x + recent_rect.width, y: recent_y } }
    let specs = [2]f64{ lsl, usl }
    i = 0usize
    while i < 2usize {
        let x = hist_rect.x + hist_rect.width * f32((specs[i] - hist_lo) / (hist_hi - hist_lo))
        work.guides[6usize + i] = Segment { from: Coord { x: x, y: hist_rect.y }, to: Coord { x: x, y: hist_rect.y + hist_rect.height } }
        i += 1usize
    }
    let guides = Layout { kind: .Rug, coords: zero, segments: work.guides[..11usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret (CapabilitySixpackLayout { individuals: individuals, moving_range: moving_range, recent: recent, histogram: hist_layout, within_curve: within_curve, overall_curve: overall_curve, probability: probability, intervals: intervals, guides: guides, summary: summary }, ok)
}

// Focused individuals normal-capability distribution. Curves are expected
// counts per bin, not probability densities; guides are LSL, mean and USL.
fn normal_capability(values: []const f64, lsl: f64, usl: f64, bounds: geometry.Rect, work: *NormalCapabilityStorage) -> (NormalCapabilityLayout, err) {
    if values.len < 5usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if work.moving.len < values.len - 1usize || work.counts.len < 2usize || work.bars.len != work.counts.len || work.within_curve.len < 63usize || work.overall_curve.len < 63usize || work.guides.len < 3usize { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.normal_capability_individuals(values, lsl, usl, work.moving)
    if summary_error != ok { ret (zero, Invalid) }
    let (performance, performance_error) = stat.normal_capability_performance(values, lsl, usl, summary)
    if performance_error != ok { ret (zero, Invalid) }
    var data_lo = values[0usize]
    var data_hi = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] < data_lo { data_lo = values[i] }
        if values[i] > data_hi { data_hi = values[i] }
        i += 1usize
    }
    let sigma = math.max[f64](summary.within_sigma, summary.overall_sigma)
    let lo = math.min[f64](lsl, math.min[f64](data_lo, summary.mean - 3.5f64 * sigma))
    let hi = math.max[f64](usl, math.max[f64](data_hi, summary.mean + 3.5f64 * sigma))
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) { ret (zero, Invalid) }
    let bins = work.counts.len
    i = 0usize
    while i < bins {
        work.counts[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        var bin = usize((values[i] - lo) / (hi - lo) * f64(bins))
        if bin >= bins { bin = bins - 1usize }
        work.counts[bin] += 1u64
        i += 1usize
    }
    let bin_width = (hi - lo) / f64(bins)
    let pi = 3.14159265358979323846f64
    var peak = f64(values.len) * bin_width / (math.min[f64](summary.within_sigma, summary.overall_sigma) * math.sqrt[f64](2.0f64 * pi))
    i = 0usize
    while i < bins {
        if f64(work.counts[i]) > peak { peak = f64(work.counts[i]) }
        i += 1usize
    }
    peak *= 1.1f64
    if !finite(f32(peak)) || !(peak > 0.0f64) { ret (zero, Invalid) }
    i = 0usize
    while i < bins {
        let h = bounds.height * f32(f64(work.counts[i]) / peak)
        work.bars[i] = geometry.rect(bounds.x + bounds.width * f32(i) / f32(bins), bounds.y + bounds.height - h, bounds.width / f32(bins), h)
        i += 1usize
    }
    let hist_layout = Layout { kind: .Histogram, coords: zero, segments: zero, bars: work.bars[..bins], x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    var prev_within: Coord = zero
    var prev_overall: Coord = zero
    i = 0usize
    while i < 64usize {
        let x = lo + (hi - lo) * f64(i) / 63.0f64
        let within_z = (x - summary.mean) / summary.within_sigma
        let overall_z = (x - summary.mean) / summary.overall_sigma
        let within_y = f64(values.len) * bin_width * math.exp[f64](-0.5f64 * within_z * within_z) / (summary.within_sigma * math.sqrt[f64](2.0f64 * pi))
        let overall_y = f64(values.len) * bin_width * math.exp[f64](-0.5f64 * overall_z * overall_z) / (summary.overall_sigma * math.sqrt[f64](2.0f64 * pi))
        let sx = bounds.x + bounds.width * f32(i) / 63.0
        let within_point = Coord { x: sx, y: bounds.y + bounds.height * (1.0 - f32(within_y / peak)) }
        let overall_point = Coord { x: sx, y: bounds.y + bounds.height * (1.0 - f32(overall_y / peak)) }
        if i > 0usize {
            work.within_curve[i - 1usize] = Segment { from: prev_within, to: within_point }
            work.overall_curve[i - 1usize] = Segment { from: prev_overall, to: overall_point }
        }
        prev_within = within_point
        prev_overall = overall_point
        i += 1usize
    }
    let within_curve = Layout { kind: .Line, coords: zero, segments: work.within_curve[..63usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    let overall_curve = Layout { kind: .Line, coords: zero, segments: work.overall_curve[..63usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    let levels = [3]f64{ lsl, summary.mean, usl }
    i = 0usize
    while i < 3usize {
        let x = bounds.x + bounds.width * f32((levels[i] - lo) / (hi - lo))
        work.guides[i] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
        i += 1usize
    }
    let guides = Layout { kind: .Rug, coords: zero, segments: work.guides[..3usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    ret (NormalCapabilityLayout { histogram: hist_layout, within_curve: within_curve, overall_curve: overall_curve, guides: guides, summary: summary, performance: performance }, ok)
}

// Overall two-parameter lognormal capability: histogram counts, fitted
// expected counts per bin, and LSL/median/USL guides in one numeric panel.
fn lognormal_capability(values: []const f64, lsl: f64, usl: f64, bounds: geometry.Rect, work: *LognormalCapabilityStorage) -> (LognormalCapabilityLayout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if work.counts.len < 2usize || work.bars.len != work.counts.len || work.fit_curve.len < 63usize || work.guides.len < 3usize { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.lognormal_capability(values, lsl, usl)
    if summary_error != ok { ret (zero, Invalid) }
    var data_lo = values[0usize]
    var data_hi = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] < data_lo { data_lo = values[i] }
        if values[i] > data_hi { data_hi = values[i] }
        i += 1usize
    }
    var lo = math.min[f64](lsl, data_lo)
    var hi = math.max[f64](usl, data_hi)
    let tail_lo = math.exp[f64](summary.log_mean - 2.8f64 * summary.log_sigma)
    let tail_hi = math.exp[f64](summary.log_mean + 2.8f64 * summary.log_sigma)
    if finite64(tail_lo) && tail_lo < lo { lo = tail_lo }
    if finite64(tail_hi) && tail_hi > hi { hi = tail_hi }
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) || !(lo > 0.0f64) { ret (zero, Invalid) }
    let bins = work.counts.len
    i = 0usize
    while i < bins {
        work.counts[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        var bin = usize((values[i] - lo) / (hi - lo) * f64(bins))
        if bin >= bins { bin = bins - 1usize }
        work.counts[bin] += 1u64
        i += 1usize
    }
    let bin_width = (hi - lo) / f64(bins)
    let pi = 3.14159265358979323846f64
    let mode = math.exp[f64](summary.log_mean - summary.log_sigma * summary.log_sigma)
    let peak_x = math.max[f64](lo, math.min[f64](hi, mode))
    let peak_z = (math.log[f64](peak_x) - summary.log_mean) / summary.log_sigma
    var peak = f64(values.len) * bin_width * math.exp[f64](-0.5f64 * peak_z * peak_z) / (peak_x * summary.log_sigma * math.sqrt[f64](2.0f64 * pi))
    i = 0usize
    while i < bins {
        if f64(work.counts[i]) > peak { peak = f64(work.counts[i]) }
        i += 1usize
    }
    peak *= 1.1f64
    if !finite(f32(peak)) || !(peak > 0.0f64) { ret (zero, Invalid) }
    i = 0usize
    while i < bins {
        let h = bounds.height * f32(f64(work.counts[i]) / peak)
        work.bars[i] = geometry.rect(bounds.x + bounds.width * f32(i) / f32(bins), bounds.y + bounds.height - h, bounds.width / f32(bins), h)
        i += 1usize
    }
    let hist_layout = Layout { kind: .Histogram, coords: zero, segments: zero, bars: work.bars[..bins], x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    var previous: Coord = zero
    i = 0usize
    while i < 64usize {
        let x = lo + (hi - lo) * f64(i) / 63.0f64
        let z = (math.log[f64](x) - summary.log_mean) / summary.log_sigma
        let expected = f64(values.len) * bin_width * math.exp[f64](-0.5f64 * z * z) / (x * summary.log_sigma * math.sqrt[f64](2.0f64 * pi))
        let point = Coord { x: bounds.x + bounds.width * f32(i) / 63.0, y: bounds.y + bounds.height * (1.0 - f32(expected / peak)) }
        if i > 0usize { work.fit_curve[i - 1usize] = Segment { from: previous, to: point } }
        previous = point
        i += 1usize
    }
    let fitted = Layout { kind: .Line, coords: zero, segments: work.fit_curve[..63usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    let levels = [3]f64{ lsl, summary.median, usl }
    i = 0usize
    while i < 3usize {
        let x = bounds.x + bounds.width * f32((levels[i] - lo) / (hi - lo))
        work.guides[i] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
        i += 1usize
    }
    let guide_layout = Layout { kind: .Rug, coords: zero, segments: work.guides[..3usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }
    ret (LognormalCapabilityLayout { histogram: hist_layout, fit_curve: fitted, guides: guide_layout, summary: summary }, ok)
}

// Binomial attribute capability: P chart and cumulative defective fraction.
// Variable inspected subgroup sizes retain their own P-chart limits.
fn binomial_capability(defectives: []const usize, inspected: []const usize, target_fraction: f64, confidence: f64, panels: []const geometry.Rect, work: *BinomialCapabilityStorage) -> (BinomialCapabilityLayout, err) {
    let n = defectives.len
    if n < 2usize || panels.len != 2usize || !valid_bounds(panels[0usize]) || !valid_bounds(panels[1usize]) { ret (zero, Invalid) }
    if work.controls.len < n || work.cumulative_rates.len < n || work.p_points.len < n || work.p_lines.len < n - 1usize || work.cumulative_points.len < n || work.cumulative_lines.len < n - 1usize || work.upper_limit.len < n - 1usize || work.lower_limit.len < n - 1usize || work.guides.len < 5usize || work.signal_points.len < n { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.binomial_capability(defectives, inspected, target_fraction, confidence, work.controls, work.cumulative_rates)
    if summary_error != ok { ret (zero, Invalid) }
    var highest = math.max[f64](summary.target_fraction, summary.confidence.high)
    var i = 0usize
    while i < n {
        if work.controls[i].value > highest { highest = work.controls[i].value }
        if work.controls[i].upper > highest { highest = work.controls[i].upper }
        i += 1usize
    }
    var y_max = math.max[f64](0.05f64, highest * 1.1f64)
    if y_max > 1.0f64 { y_max = 1.0f64 }
    if !finite(f32(y_max)) || !(y_max > 0.0f64) { ret (zero, Invalid) }
    let p_rect = panels[0usize]
    let c_rect = panels[1usize]
    var signal_count = 0usize
    i = 0usize
    while i < n {
        let subgroup_position = f32(i) / f32(n - 1usize)
        let p_x = p_rect.x + p_rect.width * subgroup_position
        let c_x = c_rect.x + c_rect.width * subgroup_position
        work.p_points[i] = Coord { x: p_x, y: p_rect.y + p_rect.height * (1.0 - f32(work.controls[i].value / y_max)) }
        work.cumulative_points[i] = Coord { x: c_x, y: c_rect.y + c_rect.height * (1.0 - f32(work.cumulative_rates[i] / y_max)) }
        if work.controls[i].value < work.controls[i].lower || work.controls[i].value > work.controls[i].upper {
            work.signal_points[signal_count] = work.p_points[i]
            signal_count += 1usize
        }
        if i > 0usize {
            work.p_lines[i - 1usize] = Segment { from: work.p_points[i - 1usize], to: work.p_points[i] }
            work.cumulative_lines[i - 1usize] = Segment { from: work.cumulative_points[i - 1usize], to: work.cumulative_points[i] }
            let before = f32(i - 1usize) / f32(n - 1usize)
            let upper_before = Coord { x: p_rect.x + p_rect.width * before, y: p_rect.y + p_rect.height * (1.0 - f32(work.controls[i - 1usize].upper / y_max)) }
            let upper_now = Coord { x: p_x, y: p_rect.y + p_rect.height * (1.0 - f32(work.controls[i].upper / y_max)) }
            let lower_before = Coord { x: p_rect.x + p_rect.width * before, y: p_rect.y + p_rect.height * (1.0 - f32(work.controls[i - 1usize].lower / y_max)) }
            let lower_now = Coord { x: p_x, y: p_rect.y + p_rect.height * (1.0 - f32(work.controls[i].lower / y_max)) }
            work.upper_limit[i - 1usize] = Segment { from: upper_before, to: upper_now }
            work.lower_limit[i - 1usize] = Segment { from: lower_before, to: lower_now }
        }
        i += 1usize
    }
    let p_chart = Layout { kind: .PointLine, coords: work.p_points[..n], segments: work.p_lines[..n - 1usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    let cumulative = Layout { kind: .PointLine, coords: work.cumulative_points[..n], segments: work.cumulative_lines[..n - 1usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    let upper_layout = Layout { kind: .Line, coords: zero, segments: work.upper_limit[..n - 1usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    let lower_layout = Layout { kind: .Line, coords: zero, segments: work.lower_limit[..n - 1usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    let guide_levels = [5]f64{ summary.fraction, summary.fraction, summary.confidence.low, summary.confidence.high, target_fraction }
    i = 0usize
    while i < 5usize {
        var rect = c_rect
        if i == 0usize { rect = p_rect }
        let y = rect.y + rect.height * (1.0 - f32(guide_levels[i] / y_max))
        work.guides[i] = Segment { from: Coord { x: rect.x, y: y }, to: Coord { x: rect.x + rect.width, y: y } }
        i += 1usize
    }
    let guide_layout = Layout { kind: .Rug, coords: zero, segments: work.guides[..5usize], bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    let signals = Layout { kind: .Scatter, coords: work.signal_points[..signal_count], segments: zero, bars: zero, x_min: 1.0, x_max: f32(n), y_min: 0.0, y_max: f32(y_max) }
    ret (BinomialCapabilityLayout { p_chart: p_chart, cumulative: cumulative, upper_limit: upper_layout, lower_limit: lower_layout, guides: guide_layout, signals: signals, summary: summary }, ok)
}

// Balanced batch capability: subgroup means, subgroup sample spread and
// specification/pooled-within guides, all in caller-owned mark storage.
fn batch_capability(values: []const f64, batch_size: usize, lsl: f64, usl: f64, panels: []const geometry.Rect, work: *BatchCapabilityStorage) -> (BatchCapabilityLayout, err) {
    if batch_size < 2usize || values.len / batch_size < 3usize || values.len % batch_size != 0usize || panels.len != 2usize || !valid_bounds(panels[0usize]) || !valid_bounds(panels[1usize]) { ret (zero, Invalid) }
    let n = values.len / batch_size
    if work.batch_means.len < n || work.batch_spreads.len < n || work.mean_points.len < n || work.mean_lines.len < n - 1usize || work.spread_bars.len < n || work.guides.len < 3usize { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.batch_capability(values, batch_size, lsl, usl, work.batch_means, work.batch_spreads)
    if summary_error != ok { ret (zero, Invalid) }
    var low = lsl
    var high = usl
    var spread_high = summary.within_sigma
    var i = 0usize
    while i < n {
        if work.batch_means[i] < low { low = work.batch_means[i] }
        if work.batch_means[i] > high { high = work.batch_means[i] }
        if work.batch_spreads[i] > spread_high { spread_high = work.batch_spreads[i] }
        i += 1usize
    }
    let pad = (high - low) * 0.1f64
    low -= pad
    high += pad
    spread_high *= 1.15f64
    if !(high > low) || !(spread_high > 0.0f64) || high - high != 0.0f64 || spread_high - spread_high != 0.0f64 { ret (zero, Invalid) }
    let mean_rect = panels[0usize]
    let spread_rect = panels[1usize]
    let bar_width = spread_rect.width / f32(n) * 0.65f32
    i = 0usize
    while i < n {
        let x_fraction = f32(i) / f32(n - 1usize)
        let mean_x = mean_rect.x + mean_rect.width * x_fraction
        let mean_y = mean_rect.y + mean_rect.height * (1.0f32 - f32((work.batch_means[i] - low) / (high - low)))
        work.mean_points[i] = Coord { x: mean_x, y: mean_y }
        if i > 0usize { work.mean_lines[i - 1usize] = Segment { from: work.mean_points[i - 1usize], to: work.mean_points[i] } }
        let center = spread_rect.x + spread_rect.width * (f32(i) + 0.5f32) / f32(n)
        let bar_height = spread_rect.height * f32(work.batch_spreads[i] / spread_high)
        work.spread_bars[i] = geometry.rect(center - bar_width * 0.5f32, spread_rect.y + spread_rect.height - bar_height, bar_width, bar_height)
        i += 1usize
    }
    let lower_y = mean_rect.y + mean_rect.height * (1.0f32 - f32((lsl - low) / (high - low)))
    let upper_y = mean_rect.y + mean_rect.height * (1.0f32 - f32((usl - low) / (high - low)))
    let within_y = spread_rect.y + spread_rect.height * (1.0f32 - f32(summary.within_sigma / spread_high))
    work.guides[0usize] = Segment { from: Coord { x: mean_rect.x, y: lower_y }, to: Coord { x: mean_rect.x + mean_rect.width, y: lower_y } }
    work.guides[1usize] = Segment { from: Coord { x: mean_rect.x, y: upper_y }, to: Coord { x: mean_rect.x + mean_rect.width, y: upper_y } }
    work.guides[2usize] = Segment { from: Coord { x: spread_rect.x, y: within_y }, to: Coord { x: spread_rect.x + spread_rect.width, y: within_y } }
    let means = Layout { kind: .PointLine, coords: work.mean_points[..n], segments: work.mean_lines[..n - 1usize], bars: zero, x_min: 1.0f32, x_max: f32(n), y_min: f32(low), y_max: f32(high) }
    let spreads = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.spread_bars[..n], x_min: 1.0f32, x_max: f32(n), y_min: 0.0f32, y_max: f32(spread_high) }
    let guides = Layout { kind: .Rug, coords: zero, segments: work.guides[..3usize], bars: zero, x_min: 1.0f32, x_max: f32(n), y_min: f32(low), y_max: f32(high) }
    ret (BatchCapabilityLayout { means: means, spreads: spreads, guides: guides, summary: summary }, ok)
}

// Bias-versus-reference plot with one mark per replicate, per-reference means,
// OLS fit and caller-critical confidence intervals for the fitted mean bias.
fn gage_linearity(references: []const f64, measurements: []const f64, repeats: usize, critical: f64, bounds: geometry.Rect, work: *GageLinearityStorage) -> (GageLinearityLayout, err) {
    if !valid_bounds(bounds) || references.len < 5usize || repeats < 2usize || measurements.len % repeats != 0usize || measurements.len / repeats != references.len { ret (zero, Invalid) }
    let q = references.len
    let n = measurements.len
    if work.biases.len < n || work.mean_biases.len < q || work.fitted_biases.len < q || work.ci_lower.len < q || work.ci_upper.len < q || work.raw_points.len < n || work.mean_points.len < q || work.fit_segments.len < q - 1usize || work.ci_segments.len < q || work.zero_guide.len < 1usize { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.gage_linearity(references, measurements, repeats, critical, work.biases, work.mean_biases, work.fitted_biases, work.ci_lower, work.ci_upper)
    if summary_error != ok { ret (zero, Invalid) }
    let x_low = references[0usize]
    let x_high = references[q - 1usize]
    var y_low = 0.0f64
    var y_high = 0.0f64
    var i = 0usize
    while i < n {
        if work.biases[i] < y_low { y_low = work.biases[i] }
        if work.biases[i] > y_high { y_high = work.biases[i] }
        i += 1usize
    }
    i = 0usize
    while i < q {
        if work.ci_lower[i] < y_low { y_low = work.ci_lower[i] }
        if work.ci_upper[i] > y_high { y_high = work.ci_upper[i] }
        i += 1usize
    }
    var span = y_high - y_low
    if !(span > 0.0f64) { span = 1.0f64 }
    y_low -= span * 0.1f64
    y_high += span * 0.1f64
    if !finite(f32(x_low)) || !finite(f32(x_high)) || !finite(f32(y_low)) || !finite(f32(y_high)) { ret (zero, Invalid) }
    i = 0usize
    while i < q {
        let x = bounds.x + bounds.width * f32((references[i] - x_low) / (x_high - x_low))
        let mean_y = bounds.y + bounds.height * (1.0f32 - f32((work.mean_biases[i] - y_low) / (y_high - y_low)))
        let fit_y = bounds.y + bounds.height * (1.0f32 - f32((work.fitted_biases[i] - y_low) / (y_high - y_low)))
        let lower_y = bounds.y + bounds.height * (1.0f32 - f32((work.ci_lower[i] - y_low) / (y_high - y_low)))
        let upper_y = bounds.y + bounds.height * (1.0f32 - f32((work.ci_upper[i] - y_low) / (y_high - y_low)))
        work.mean_points[i] = Coord { x: x, y: mean_y }
        work.ci_segments[i] = Segment { from: Coord { x: x, y: lower_y }, to: Coord { x: x, y: upper_y } }
        if i > 0usize {
            let before = bounds.x + bounds.width * f32((references[i - 1usize] - x_low) / (x_high - x_low))
            let before_y = bounds.y + bounds.height * (1.0f32 - f32((work.fitted_biases[i - 1usize] - y_low) / (y_high - y_low)))
            work.fit_segments[i - 1usize] = Segment { from: Coord { x: before, y: before_y }, to: Coord { x: x, y: fit_y } }
        }
        var j = 0usize
        while j < repeats {
            let index = i * repeats + j
            let y = bounds.y + bounds.height * (1.0f32 - f32((work.biases[index] - y_low) / (y_high - y_low)))
            work.raw_points[index] = Coord { x: x, y: y }
            j += 1usize
        }
        i += 1usize
    }
    let zero_y = bounds.y + bounds.height * (1.0f32 - f32((0.0f64 - y_low) / (y_high - y_low)))
    work.zero_guide[0usize] = Segment { from: Coord { x: bounds.x, y: zero_y }, to: Coord { x: bounds.x + bounds.width, y: zero_y } }
    let observations = Layout { kind: .Scatter, coords: work.raw_points[..n], segments: zero, bars: zero, x_min: f32(x_low), x_max: f32(x_high), y_min: f32(y_low), y_max: f32(y_high) }
    let means = Layout { kind: .Scatter, coords: work.mean_points[..q], segments: zero, bars: zero, x_min: f32(x_low), x_max: f32(x_high), y_min: f32(y_low), y_max: f32(y_high) }
    let fit = Layout { kind: .Line, coords: zero, segments: work.fit_segments[..q - 1usize], bars: zero, x_min: f32(x_low), x_max: f32(x_high), y_min: f32(y_low), y_max: f32(y_high) }
    let confidence = Layout { kind: .ErrorBar, coords: zero, segments: work.ci_segments[..q], bars: zero, x_min: f32(x_low), x_max: f32(x_high), y_min: f32(y_low), y_max: f32(y_high) }
    let zero_line = Layout { kind: .Rug, coords: zero, segments: work.zero_guide[..1usize], bars: zero, x_min: f32(x_low), x_max: f32(x_high), y_min: f32(y_low), y_max: f32(y_high) }
    ret (GageLinearityLayout { observations: observations, means: means, fit: fit, confidence: confidence, zero_line: zero_line, summary: summary }, ok)
}

// Two-pane nominal attribute-agreement plot: consistent trials and consistent
// correct trials per appraiser, each with exact binomial intervals.
fn attribute_agreement(standard: []const usize, ratings: []const usize, appraisers: usize, trials: usize, categories: usize, confidence: f64, panels: []const geometry.Rect, work: *AttributeAgreementStorage) -> (AttributeAgreementLayout, err) {
    if panels.len != 2usize || !valid_bounds(panels[0usize]) || !valid_bounds(panels[1usize]) || appraisers < 2usize { ret (zero, Invalid) }
    if work.within_rates.len < appraisers || work.standard_rates.len < appraisers || work.within_points.len < appraisers || work.standard_points.len < appraisers || work.within_intervals.len < appraisers || work.standard_intervals.len < appraisers { ret (zero, TooLarge) }
    let (summary, summary_error) = stat.attribute_agreement(standard, ratings, appraisers, trials, categories, confidence, work.within_rates, work.standard_rates)
    if summary_error != ok { ret (zero, Invalid) }
    var i = 0usize
    while i < appraisers {
        let w = work.within_rates[i]
        let s = work.standard_rates[i]
        let wx = panels[0usize].x + panels[0usize].width * (f32(i) + 0.5f32) / f32(appraisers)
        let sx = panels[1usize].x + panels[1usize].width * (f32(i) + 0.5f32) / f32(appraisers)
        work.within_points[i] = Coord { x: wx, y: panels[0usize].y + panels[0usize].height * (1.0f32 - f32(w.fraction)) }
        work.standard_points[i] = Coord { x: sx, y: panels[1usize].y + panels[1usize].height * (1.0f32 - f32(s.fraction)) }
        work.within_intervals[i] = Segment {
            from: Coord { x: wx, y: panels[0usize].y + panels[0usize].height * (1.0f32 - f32(w.confidence.low)) },
            to: Coord { x: wx, y: panels[0usize].y + panels[0usize].height * (1.0f32 - f32(w.confidence.high)) },
        }
        work.standard_intervals[i] = Segment {
            from: Coord { x: sx, y: panels[1usize].y + panels[1usize].height * (1.0f32 - f32(s.confidence.low)) },
            to: Coord { x: sx, y: panels[1usize].y + panels[1usize].height * (1.0f32 - f32(s.confidence.high)) },
        }
        i += 1usize
    }
    let within_marks = Layout { kind: .Scatter, coords: work.within_points[..appraisers], segments: zero, bars: zero, x_min: 1.0f32, x_max: f32(appraisers), y_min: 0.0f32, y_max: 1.0f32 }
    let within_ci = Layout { kind: .ErrorBar, coords: zero, segments: work.within_intervals[..appraisers], bars: zero, x_min: 1.0f32, x_max: f32(appraisers), y_min: 0.0f32, y_max: 1.0f32 }
    let standard_marks = Layout { kind: .Scatter, coords: work.standard_points[..appraisers], segments: zero, bars: zero, x_min: 1.0f32, x_max: f32(appraisers), y_min: 0.0f32, y_max: 1.0f32 }
    let standard_ci = Layout { kind: .ErrorBar, coords: zero, segments: work.standard_intervals[..appraisers], bars: zero, x_min: 1.0f32, x_max: f32(appraisers), y_min: 0.0f32, y_max: 1.0f32 }
    ret (AttributeAgreementLayout { within: within_marks, within_intervals: within_ci, versus_standard: standard_marks, standard_intervals: standard_ci, summary: summary }, ok)
}

// Crossed gage run chart: every replicate remains visible, colored by operator
// by the caller; part dividers and the grand-mean reference are separate layers.
fn gage_run(values: []const f64, parts: usize, operators: usize, repeats: usize, bounds: geometry.Rect, work: *GageRunStorage) -> (GageRunLayout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let (summary, summary_error) = stat.gage_run_summary(values, parts, operators, repeats)
    if summary_error != ok { ret (zero, Invalid) }
    if work.operator_points.len < values.len || work.operator_layouts.len < operators || work.part_centers.len < parts || work.part_dividers.len < parts - 1usize || work.mean_guide.len < 1usize { ret (zero, TooLarge) }
    let spread = summary.maximum - summary.minimum
    var padding = spread * 0.08f64
    if spread == 0.0f64 {
        padding = math.abs[f64](summary.minimum) * 0.05f64
        if padding == 0.0f64 { padding = 1.0f64 }
    }
    let y_low = summary.minimum - padding
    let y_high = summary.maximum + padding
    let y_span = y_high - y_low
    if !finite64(y_low) || !finite64(y_high) || !finite64(y_span) || !(y_span > 0.0f64) || !finite(f32(y_low)) || !finite(f32(y_high)) { ret (zero, Invalid) }
    var part = 0usize
    while part < parts {
        let part_x = bounds.x + bounds.width * (f32(part) + 0.5f32) / f32(parts)
        work.part_centers[part] = Coord { x: part_x, y: bounds.y + bounds.height }
        if part > 0usize {
            let divider_x = bounds.x + bounds.width * f32(part) / f32(parts)
            work.part_dividers[part - 1usize] = Segment {
                from: Coord { x: divider_x, y: bounds.y },
                to: Coord { x: divider_x, y: bounds.y + bounds.height },
            }
        }
        var operator = 0usize
        while operator < operators {
            var trial = 0usize
            while trial < repeats {
                let value = values[(part * operators + operator) * repeats + trial]
                let x_fraction = (f32(part) + (f32(operator) + (f32(trial) + 0.5f32) / f32(repeats)) / f32(operators)) / f32(parts)
                let y_fraction = f32((value - y_low) / y_span)
                let index = (operator * parts + part) * repeats + trial
                work.operator_points[index] = Coord {
                    x: bounds.x + bounds.width * x_fraction,
                    y: bounds.y + bounds.height * (1.0f32 - y_fraction),
                }
                trial += 1usize
            }
            operator += 1usize
        }
        part += 1usize
    }
    let mean_y = bounds.y + bounds.height * (1.0f32 - f32((summary.grand_mean - y_low) / y_span))
    work.mean_guide[0usize] = Segment {
        from: Coord { x: bounds.x, y: mean_y },
        to: Coord { x: bounds.x + bounds.width, y: mean_y },
    }
    var operator = 0usize
    while operator < operators {
        let start = operator * parts * repeats
        let end = start + parts * repeats
        work.operator_layouts[operator] = Layout {
            kind: .Scatter, coords: work.operator_points[start..end], segments: zero, bars: zero,
            x_min: 0.0f32, x_max: f32(parts), y_min: f32(y_low), y_max: f32(y_high),
        }
        operator += 1usize
    }
    let dividers = Layout { kind: .Rug, coords: zero, segments: work.part_dividers[..parts - 1usize], bars: zero, x_min: 0.0f32, x_max: f32(parts), y_min: f32(y_low), y_max: f32(y_high) }
    let reference = Layout { kind: .Rug, coords: zero, segments: work.mean_guide[..1usize], bars: zero, x_min: 0.0f32, x_max: f32(parts), y_min: f32(y_low), y_max: f32(y_high) }
    ret (GageRunLayout { operators: work.operator_layouts[..operators], part_centers: work.part_centers[..parts], dividers: dividers, reference: reference, summary: summary }, ok)
}

fn map_point(lon: f64, lat: f64, window: geo.MapWindow, bounds: geometry.Rect) -> (Coord, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let (x, y, project_error) = geo.map_project(lon, lat, window)
    if project_error != ok { ret (zero, Invalid) }
    let point = Coord { x: bounds.x + bounds.width * f32(x), y: bounds.y + bounds.height * f32(y) }
    if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
    ret (point, ok)
}

// A region owns contiguous rings; each ring owns contiguous WGS84 vertices.
// The first ring of each region is exterior. Reversed projected winding makes
// holes subtract under both scene's nonzero fill and SVG's nonzero fill.
fn choropleth(regions: []const MapRegion, rings: []const MapRing, vertices: []const MapVertex, metrics: []const MapMetric, window: geo.MapWindow, bounds: geometry.Rect, work: *ChoroplethStorage) -> (ChoroplethLayout, err) {
    if !valid_bounds(bounds) || regions.len == 0usize || rings.len < regions.len || vertices.len / 3usize < rings.len { ret (zero, Invalid) }
    if work.points.len < vertices.len || work.rings.len < rings.len || work.regions.len < regions.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < regions.len {
        if regions[i].key.len == 0usize { ret (zero, Invalid) }
        var prior = 0usize
        while prior < i {
            if str.eq(regions[prior].key, regions[i].key) { ret (zero, Invalid) }
            prior += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < metrics.len {
        if metrics[i].key.len == 0usize || !finite64(metrics[i].value) { ret (zero, Invalid) }
        var prior = 0usize
        while prior < i {
            if str.eq(metrics[prior].key, metrics[i].key) { ret (zero, Invalid) }
            prior += 1usize
        }
        i += 1usize
    }
    var minimum = 0.0f64
    var maximum = 0.0f64
    var has_values = false
    i = 0usize
    while i < regions.len {
        var metric = 0usize
        while metric < metrics.len {
            if str.eq(regions[i].key, metrics[metric].key) {
                let value = metrics[metric].value
                if !has_values || value < minimum { minimum = value }
                if !has_values || value > maximum { maximum = value }
                has_values = true
                break
            }
            metric += 1usize
        }
        i += 1usize
    }
    let spread = maximum - minimum
    if !finite64(spread) { ret (zero, Invalid) }
    var ring_index = 0usize
    var vertex_index = 0usize
    i = 0usize
    while i < regions.len {
        let ring_start = ring_index
        var has_outer = false
        while ring_index < rings.len && rings[ring_index].region == i {
            let ring = rings[ring_index]
            if ring.first != vertex_index || ring.count < 3usize || ring.count > vertices.len - vertex_index || (ring.hole && !has_outer) { ret (zero, Invalid) }
            if !ring.hole { has_outer = true }
            var edge = 0usize
            while edge < ring.count {
                let vertex = vertices[vertex_index + edge]
                let (point, point_error) = map_point(vertex.lon, vertex.lat, window, bounds)
                if point_error != ok { ret (zero, Invalid) }
                work.points[vertex_index + edge] = point
                edge += 1usize
            }
            var area = 0.0f64
            edge = 0usize
            while edge < ring.count {
                let next = (edge + 1usize) % ring.count
                let a = work.points[vertex_index + edge]
                let b = work.points[vertex_index + next]
                // A wrapped jump over 180 degrees still straddles the seam.
                if math.abs[f64](f64(a.x - b.x) / f64(bounds.width) * 2.0f64 * window.half_lon_span) > 180.0f64 { ret (zero, Invalid) }
                area += f64(a.x) * f64(b.y) - f64(b.x) * f64(a.y)
                edge += 1usize
            }
            if !finite64(area) || math.abs[f64](area) < 0.000001f64 { ret (zero, Invalid) }
            var reverse = area < 0.0f64
            if ring.hole { reverse = area > 0.0f64 }
            work.rings[ring_index] = MapProjectedRing { first: vertex_index, count: ring.count, hole: ring.hole, reverse: reverse }
            vertex_index += ring.count
            ring_index += 1usize
        }
        if !has_outer { ret (zero, Invalid) }
        var found = false
        var value = 0.0f64
        var metric = 0usize
        while metric < metrics.len {
            if str.eq(regions[i].key, metrics[metric].key) {
                found = true
                value = metrics[metric].value
                break
            }
            metric += 1usize
        }
        var value_fraction = 0.0f32
        if found {
            value_fraction = 0.5f32
            if spread > 0.0f64 { value_fraction = f32((value - minimum) / spread) }
        }
        work.regions[i] = MapRegionLayout {
            key: regions[i].key, rings: work.rings[ring_start..ring_index],
            points: work.points[..vertices.len], has_value: found, value: value, fraction: value_fraction,
        }
        i += 1usize
    }
    if ring_index != rings.len || vertex_index != vertices.len { ret (zero, Invalid) }
    ret (ChoroplethLayout { regions: work.regions[..regions.len], minimum: minimum, maximum: maximum, has_values: has_values }, ok)
}

// Circle area, not radius, is proportional to a nonnegative site value.
fn proportional_symbol_map(sites: []const MapSite, window: geo.MapWindow, bounds: geometry.Rect, max_radius: f32, bars: []geometry.Rect) -> (ProportionalMapLayout, err) {
    if !valid_bounds(bounds) || sites.len == 0usize || !finite(max_radius) || max_radius <= 0.0f32 { ret (zero, Invalid) }
    if bars.len < sites.len { ret (zero, TooLarge) }
    var maximum = 0.0f64
    var present_count = 0usize
    var i = 0usize
    while i < sites.len {
        if sites[i].key.len == 0usize || !finite64(sites[i].value) || sites[i].value < 0.0f64 { ret (zero, Invalid) }
        let (_, point_error) = map_point(sites[i].lon, sites[i].lat, window, bounds)
        if point_error != ok { ret (zero, Invalid) }
        if sites[i].present {
            present_count += 1usize
            if sites[i].value > maximum { maximum = sites[i].value }
        }
        i += 1usize
    }
    i = 0usize
    while i < sites.len {
        bars[i] = geometry.rect(0.0, 0.0, 0.0, 0.0)
        if sites[i].present && sites[i].value > 0.0f64 && maximum > 0.0f64 {
            let (point, _) = map_point(sites[i].lon, sites[i].lat, window, bounds)
            let radius = max_radius * f32(math.sqrt[f64](sites[i].value / maximum))
            bars[i] = geometry.rect(point.x - radius, point.y - radius, 2.0f32 * radius, 2.0f32 * radius)
        }
        i += 1usize
    }
    let marks = Layout { kind: .Bubble, coords: zero, segments: zero, bars: bars[..sites.len], x_min: 0.0f32, x_max: 1.0f32, y_min: 0.0f32, y_max: 1.0f32 }
    ret (ProportionalMapLayout { marks: marks, maximum: maximum, present_count: present_count }, ok)
}

fn report_grid_valid(bounds: geometry.Rect, header_width: f32, rows: usize, columns: usize) -> bool {
    if !valid_bounds(bounds) || rows == 0usize || columns == 0usize || !finite(header_width) || header_width < 20.0f32 || header_width >= bounds.width { ret false }
    ret (bounds.width - header_width) / f32(columns + 1usize) > 8.0f32 && bounds.height / f32(rows + 2usize) > 10.0f32
}

fn report_rect(bounds: geometry.Rect, header_width: f32, rows: usize, columns: usize, row: usize, column: usize) -> geometry.Rect {
    let body_width = (bounds.width - header_width) / f32(columns + 1usize)
    let row_height = bounds.height / f32(rows + 2usize)
    var x = bounds.x
    var width = header_width
    if column > 0usize {
        x = bounds.x + header_width + f32(column - 1usize) * body_width
        width = body_width
    }
    ret geometry.rect(x + 0.5f32, bounds.y + f32(row) * row_height + 0.5f32, width - 1.0f32, row_height - 1.0f32)
}

fn report_cell(bounds: geometry.Rect, header_width: f32, rows: usize, columns: usize, row: usize, column: usize, kind: ReportCellKind, value: f64, present: bool, source: usize) -> ReportCell {
    ret ReportCell {
        rect: report_rect(bounds, header_width, rows, columns, row, column),
        bar: geometry.rect(0.0, 0.0, 0.0, 0.0),
        kind: kind, value: value, present: present, source: source,
    }
}

// One header row/column and one marginal-total row/column around exact counts.
fn cross_tab_report(row_ids: []const usize, column_ids: []const usize, rows: usize, columns: usize, bounds: geometry.Rect, header_width: f32, work: *CrossTabStorage) -> (CrossTabLayout, err) {
    if !report_grid_valid(bounds, header_width, rows, columns) { ret (zero, Invalid) }
    let display_rows = rows + 2usize
    let display_columns = columns + 2usize
    if display_rows > work.cells.len / display_columns { ret (zero, TooLarge) }
    let (summary, aggregate_error) = stat.cross_tabulate(row_ids, column_ids, rows, columns, work.counts, work.row_totals, work.column_totals)
    if aggregate_error != ok { ret (zero, aggregate_error) }
    var row = 0usize
    while row < display_rows {
        var column = 0usize
        while column < display_columns {
            var kind = ReportCellKind.Body
            var value = 0.0f64
            var source = 0usize
            if row == 0usize {
                kind = .ColumnHeader
                if column == 0usize { kind = .Corner } else { source = column - 1usize }
            } else if row == display_rows - 1usize {
                kind = .ColumnTotal
                if column == display_columns - 1usize {
                    kind = .GrandTotal
                    value = f64(summary.total)
                } else if column > 0usize {
                    value = f64(work.column_totals[column - 1usize])
                }
            } else if column == 0usize {
                kind = .RowHeader
                source = row - 1usize
            } else if column == display_columns - 1usize {
                kind = .RowTotal
                value = f64(work.row_totals[row - 1usize])
                source = row - 1usize
            } else {
                value = f64(work.counts[(row - 1usize) * columns + column - 1usize])
                source = row - 1usize
            }
            let numeric = row > 0usize && column > 0usize
            work.cells[row * display_columns + column] = report_cell(bounds, header_width, rows, columns, row, column, kind, value, numeric, source)
            column += 1usize
        }
        row += 1usize
    }
    ret (CrossTabLayout { cells: work.cells[..display_rows * display_columns], summary: summary, display_rows: display_rows, display_columns: display_columns }, ok)
}

// Leaf rows are contiguous by group; a subtotal row follows each group.
// Data bars use positive sums and an explicit row/global normalization scope.
fn matrix_report(row_ids: []const usize, column_ids: []const usize, values: []const f64, present: []const bool, group_ids: []const usize, rows: usize, columns: usize, bounds: geometry.Rect, header_width: f32, bar_scope: ReportBarScope, work: *MatrixReportStorage) -> (MatrixReportLayout, err) {
    if rows == 0usize || group_ids.len != rows || group_ids[0usize] != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    var group_count = 1usize
    var row = 1usize
    while row < rows {
        if group_ids[row] < group_ids[row - 1usize] || group_ids[row] > group_ids[row - 1usize] + 1usize { ret (zero, Invalid) }
        if group_ids[row] == group_count { group_count += 1usize }
        row += 1usize
    }
    let display_rows = rows + group_count + 2usize
    let display_columns = columns + 2usize
    if !report_grid_valid(bounds, header_width, rows + group_count, columns) { ret (zero, Invalid) }
    if display_rows > work.cells.len / display_columns || group_count > work.group_totals.len || group_count > work.group_aggregates.len / columns { ret (zero, TooLarge) }
    let (grand, aggregate_error) = stat.matrix_aggregate(row_ids, column_ids, values, present, rows, columns, work.aggregates, work.row_totals, work.column_totals)
    if aggregate_error != ok { ret (zero, aggregate_error) }
    var i = 0usize
    while i < group_count * columns {
        work.group_aggregates[i] = stat.ReportAggregate { sum: 0.0f64, count: 0usize }
        i += 1usize
    }
    i = 0usize
    while i < group_count {
        work.group_totals[i] = stat.ReportAggregate { sum: 0.0f64, count: 0usize }
        i += 1usize
    }
    var global_max = 0.0f64
    row = 0usize
    while row < rows {
        var column = 0usize
        while column < columns {
            let aggregate = work.aggregates[row * columns + column]
            let group_index = group_ids[row] * columns + column
            work.group_aggregates[group_index].sum += aggregate.sum
            work.group_aggregates[group_index].count += aggregate.count
            if aggregate.count > 0usize {
                if bar_scope != .None && aggregate.sum < 0.0f64 { ret (zero, Invalid) }
                if aggregate.sum > global_max { global_max = aggregate.sum }
            }
            column += 1usize
        }
        work.group_totals[group_ids[row]].sum += work.row_totals[row].sum
        work.group_totals[group_ids[row]].count += work.row_totals[row].count
        row += 1usize
    }
    i = 0usize
    while i < group_count * columns {
        if !finite64(work.group_aggregates[i].sum) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < group_count {
        if !finite64(work.group_totals[i].sum) { ret (zero, Invalid) }
        i += 1usize
    }
    // Header row.
    var column = 0usize
    while column < display_columns {
        var kind = ReportCellKind.ColumnHeader
        if column == 0usize { kind = .Corner }
        work.cells[column] = report_cell(bounds, header_width, rows + group_count, columns, 0usize, column, kind, 0.0f64, false, column)
        column += 1usize
    }
    var display_row = 1usize
    row = 0usize
    while row < rows {
        column = 0usize
        var row_max = 0.0f64
        while column < columns {
            let aggregate = work.aggregates[row * columns + column]
            if aggregate.count > 0usize && aggregate.sum > row_max { row_max = aggregate.sum }
            column += 1usize
        }
        column = 0usize
        while column < display_columns {
            var kind = ReportCellKind.Body
            var aggregate: stat.ReportAggregate = zero
            if column == 0usize { kind = .RowHeader }
            if column == display_columns - 1usize {
                kind = .RowTotal
                aggregate = work.row_totals[row]
            } else if column > 0usize {
                aggregate = work.aggregates[row * columns + column - 1usize]
            }
            let index = display_row * display_columns + column
            work.cells[index] = report_cell(bounds, header_width, rows + group_count, columns, display_row, column, kind, aggregate.sum, aggregate.count > 0usize, row)
            if kind == .Body && aggregate.count > 0usize && aggregate.sum > 0.0f64 && bar_scope != .None {
                var denominator = global_max
                if bar_scope == .Row { denominator = row_max }
                if denominator > 0.0f64 {
                    let cell = work.cells[index].rect
                    work.cells[index].bar = geometry.rect(cell.x + 3.0f32, cell.y + cell.height * 0.65f32, (cell.width - 6.0f32) * f32(aggregate.sum / denominator), cell.height * 0.22f32)
                }
            }
            column += 1usize
        }
        display_row += 1usize
        if row == rows - 1usize || group_ids[row + 1usize] != group_ids[row] {
            column = 0usize
            while column < display_columns {
                var aggregate: stat.ReportAggregate = zero
                if column == display_columns - 1usize {
                    aggregate = work.group_totals[group_ids[row]]
                } else if column > 0usize {
                    aggregate = work.group_aggregates[group_ids[row] * columns + column - 1usize]
                }
                work.cells[display_row * display_columns + column] = report_cell(bounds, header_width, rows + group_count, columns, display_row, column, .GroupSubtotal, aggregate.sum, aggregate.count > 0usize, group_ids[row])
                column += 1usize
            }
            display_row += 1usize
        }
        row += 1usize
    }
    column = 0usize
    while column < display_columns {
        var kind = ReportCellKind.ColumnTotal
        var aggregate: stat.ReportAggregate = zero
        if column == display_columns - 1usize {
            kind = .GrandTotal
            aggregate = grand
        } else if column > 0usize {
            aggregate = work.column_totals[column - 1usize]
        }
        work.cells[display_row * display_columns + column] = report_cell(bounds, header_width, rows + group_count, columns, display_row, column, kind, aggregate.sum, aggregate.count > 0usize, 0usize)
        column += 1usize
    }
    ret (MatrixReportLayout { cells: work.cells[..display_rows * display_columns], grand: grand, display_rows: display_rows, display_columns: display_columns, group_count: group_count }, ok)
}

// A sparkline is an evenly spaced Line with no guide contract.
fn sparkline(values: []const f32, bounds: geometry.Rect, x: []f32, segments: []Segment) -> (Layout, err) {
    if values.len < 2usize { ret (zero, Empty) }
    if x.len < values.len || segments.len < values.len - 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        x[i] = f32(i)
        i += 1usize
    }
    let plot = spec(.Line, bounds, x[..values.len], values)
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, marks_error) = layout(&plot, unused_coords[..0usize], segments, unused_bars[..0usize])
    ret (marks, marks_error)
}

// Four diagnostic curves from one tie-grouped classifier threshold sweep.
fn binary_metric_curve(c: *const stat.BinaryCurve, metric: BinaryMetric, bounds: geometry.Rect, x: []f32, y: []f32, segments: []Segment) -> (Layout, err) {
    let (_, valid) = stat.roc_auc(c)
    if !valid || !valid_bounds(bounds) { ret (zero, Invalid) }
    if x.len < c.points.len || y.len < c.points.len || segments.len + 1usize < c.points.len { ret (zero, TooLarge) }
    let total = c.positives + c.negatives
    let prevalence = f64(c.positives) / f64(total)
    var ymax = 1.0f32
    var i = 0usize
    while i < c.points.len {
        let p = c.points[i]
        let selected = p.tp + p.fp
        if metric == .Roc {
            x[i] = f32(f64(p.fp) / f64(c.negatives))
            y[i] = f32(f64(p.tp) / f64(c.positives))
        } else if metric == .PrecisionRecall {
            x[i] = f32(f64(p.tp) / f64(c.positives))
            y[i] = 1.0
            if selected > 0usize { y[i] = f32(f64(p.tp) / f64(selected)) }
        } else if metric == .CumulativeGain {
            x[i] = f32(f64(selected) / f64(total))
            y[i] = f32(f64(p.tp) / f64(c.positives))
        } else {
            x[i] = f32(f64(selected) / f64(total))
            y[i] = 1.0
            if selected > 0usize { y[i] = f32((f64(p.tp) / f64(selected)) / prevalence) }
        }
        if !finite(x[i]) || !finite(y[i]) { ret (zero, Invalid) }
        if y[i] > ymax { ymax = y[i] }
        i += 1usize
    }
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ 0.0, ymax }
    let plot = spec(.Line, bounds, x[..c.points.len], y[..c.points.len])
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, layout_error) = layout_with_limits(&plot, unused_coords[..0usize], segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    ret (marks, layout_error)
}

// Fill the raw partial-AUC region on the full [0, 1] ROC axes.
fn roc_partial_region(c: *const stat.BinaryCurve, max_fpr: f32, bounds: geometry.Rect, points: []Coord) -> (Layout, err) {
    let (_, valid) = stat.roc_partial_auc(c, f64(max_fpr))
    if !valid || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < c.points.len + 2usize { ret (zero, TooLarge) }
    let bottom = bounds.y + bounds.height
    points[0usize] = Coord { x: bounds.x, y: bottom }
    var used = 1usize
    var i = 0usize
    while i < c.points.len {
        let p = c.points[i]
        let x = f32(f64(p.fp) / f64(c.negatives))
        let y = f32(f64(p.tp) / f64(c.positives))
        if x <= max_fpr {
            points[used] = Coord { x: bounds.x + bounds.width * x, y: bottom - bounds.height * y }
            used += 1usize
        } else {
            let before = c.points[i - 1usize]
            let x0 = f64(before.fp) / f64(c.negatives)
            let y0 = f64(before.tp) / f64(c.positives)
            let x1 = f64(p.fp) / f64(c.negatives)
            let y1 = f64(p.tp) / f64(c.positives)
            let y_stop = y0 + (y1 - y0) * (f64(max_fpr) - x0) / (x1 - x0)
            points[used] = Coord { x: bounds.x + bounds.width * max_fpr, y: bottom - bounds.height * f32(y_stop) }
            used += 1usize
            break
        }
        i += 1usize
    }
    points[used] = Coord { x: bounds.x + bounds.width * max_fpr, y: bottom }
    used += 1usize
    ret (Layout { kind: .Area, coords: points[..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }, ok)
}

// One bar per caller-supplied cell, all measured against the same maximum.
fn in_cell_bars(values: []const f32, maximum: f32, cells: []const geometry.Rect, inset: f32, bars: []geometry.Rect) -> (Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if cells.len != values.len || !finite(maximum) || maximum <= 0.0 || !finite(inset) || inset < 0.0 { ret (zero, Invalid) }
    if bars.len < values.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        let cell = cells[i]
        if !valid_bounds(cell) || cell.width <= inset * 2.0 || cell.height <= inset * 2.0 || !finite(values[i]) || values[i] < 0.0 || values[i] > maximum { ret (zero, Invalid) }
        bars[i] = geometry.rect(cell.x + inset, cell.y + inset, (cell.width - 2.0 * inset) * (values[i] / maximum), cell.height - 2.0 * inset)
        i += 1usize
    }
    ret (Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..values.len], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: f32(values.len) }, ok)
}

// Empty limits use each series' own domain; two values fix the domain so
// multiple facet panels can share x, y, or both without copying their columns.
fn layout_with_limits(s: *const Spec, coords: []Coord, segments: []Segment, bars: []geometry.Rect, x_limits: []const f32, y_limits: []const f32) -> (Layout, err) {
    if s.kind == .PointLine {
        if coords.len < s.x.len || (s.x.len > 1usize && segments.len < s.x.len - 1usize) { ret (zero, TooLarge) }
        var points_spec = *s
        points_spec.kind = .Scatter
        let (points, points_error) = layout_with_limits(&points_spec, coords, segments, bars, x_limits, y_limits)
        if points_error != ok { ret (zero, points_error) }
        var line_spec = *s
        line_spec.kind = .Line
        let (line, line_error) = layout_with_limits(&line_spec, coords, segments, bars, x_limits, y_limits)
        if line_error != ok { ret (zero, line_error) }
        ret (Layout { kind: .PointLine, coords: points.coords, segments: line.segments, bars: zero, x_min: points.x_min, x_max: points.x_max, y_min: points.y_min, y_max: points.y_max }, ok)
    }
    if s.kind == .Histogram || s.kind == .Ecdf || s.kind == .Box || s.kind == .Density || s.kind == .Qq || s.kind == .Violin || s.kind == .Heatmap || s.kind == .Correlation || s.kind == .ErrorBar || s.kind == .Band || s.kind == .Dumbbell || s.kind == .SlopeGraph || s.kind == .FrequencyPolygon || s.kind == .Rug || s.kind == .Strip || s.kind == .Beeswarm || s.kind == .DotPlot || s.kind == .Bubble { ret (zero, Invalid) }
    if s.x.len == 0usize { ret (zero, Empty) }
    if s.x.len != s.y.len || s.bounds.width <= 0.0 || s.bounds.height <= 0.0 { ret (zero, Invalid) }
    if (x_limits.len != 0usize && x_limits.len != 2usize) || (y_limits.len != 0usize && y_limits.len != 2usize) { ret (zero, Invalid) }
    if !finite(s.bounds.x) || !finite(s.bounds.y) || !finite(s.bounds.width) || !finite(s.bounds.height) { ret (zero, Invalid) }
    let (x0, x1, x_error) = extent(s.x)
    if x_error != ok { ret (zero, x_error) }
    let (raw_y0, raw_y1, y_error) = extent(s.y)
    if y_error != ok { ret (zero, y_error) }
    var y0 = raw_y0
    var y1 = raw_y1
    if s.kind == .Bar || s.kind == .Area || s.kind == .Lollipop {
        if !finite(s.baseline) { ret (zero, Invalid) }
        if s.baseline < y0 { y0 = s.baseline }
        if s.baseline > y1 { y1 = s.baseline }
    }
    var xmin = x0
    var xmax = x1
    if s.kind == .Bar && s.x_scale.kind == .Linear && s.x.len > 1usize && x_limits.len == 0usize {
        let pad = f32((f64(x1) - f64(x0)) / f64(s.x.len - 1usize) / 2.0f64)
        let left = x0 - pad
        let right = x1 + pad
        if finite(left) && finite(right) {
            xmin = left
            xmax = right
        }
    }
    if x_limits.len == 2usize {
        if !valid_scale(s.x_scale, x_limits[0usize], x_limits[1usize]) || x_limits[0usize] > x0 || x_limits[1usize] < x1 { ret (zero, Invalid) }
        xmin = x_limits[0usize]
        xmax = x_limits[1usize]
    }
    if y_limits.len == 2usize {
        if !valid_scale(s.y_scale, y_limits[0usize], y_limits[1usize]) || y_limits[0usize] > y0 || y_limits[1usize] < y1 { ret (zero, Invalid) }
        y0 = y_limits[0usize]
        y1 = y_limits[1usize]
    }
    if xmin == xmax {
        if s.x_scale.kind == .Log10 {
            if !(xmin > 0.0) { ret (zero, Invalid) }
            xmin = x0 / 2.0
            xmax = x0 * 2.0
            if !(xmin > 0.0) { xmin = x0 }
            if !finite(xmax) { xmax = x0 }
        } else {
            xmin -= 0.5
            xmax += 0.5
        }
    }
    if y0 == y1 {
        if s.y_scale.kind == .Log10 {
            if !(y0 > 0.0) { ret (zero, Invalid) }
            let constant = y0
            y0 = constant / 2.0
            y1 = constant * 2.0
            if !(y0 > 0.0) { y0 = constant }
            if !finite(y1) { y1 = constant }
        } else {
            y0 -= 0.5
            y1 += 0.5
        }
    }
    if !valid_scale(s.x_scale, xmin, xmax) || !valid_scale(s.y_scale, y0, y1) { ret (zero, Invalid) }

    var coord_count = 0usize
    var segment_count = 0usize
    var bar_count = 0usize
    if s.kind == .Scatter {
        if coords.len < s.x.len { ret (zero, TooLarge) }
        while coord_count < s.x.len {
            coords[coord_count] = Coord {
                x: x_position(s, s.x[coord_count], xmin, xmax),
                y: y_position(s, s.y[coord_count], y0, y1),
            }
            coord_count += 1usize
        }
    } else if s.kind == .Line {
        if segments.len + 1usize < s.x.len { ret (zero, TooLarge) }
        if s.x.len > 1usize {
            while segment_count + 1usize < s.x.len {
                let from = Coord {
                    x: x_position(s, s.x[segment_count], xmin, xmax),
                    y: y_position(s, s.y[segment_count], y0, y1),
                }
                let next = segment_count + 1usize
                let to = Coord {
                    x: x_position(s, s.x[next], xmin, xmax),
                    y: y_position(s, s.y[next], y0, y1),
                }
                segments[segment_count] = Segment { from: from, to: to }
                segment_count += 1usize
            }
        }
    } else if s.kind == .Area {
        if s.x.len < 2usize { ret (zero, Empty) }
        if coords.len / 2usize < s.x.len { ret (zero, TooLarge) }
        let baseline_y = y_position(s, s.baseline, y0, y1)
        var i = 0usize
        while i < s.x.len {
            if i > 0usize && s.x[i] < s.x[i - 1usize] { ret (zero, Invalid) }
            let x = x_position(s, s.x[i], xmin, xmax)
            coords[i] = Coord { x: x, y: y_position(s, s.y[i], y0, y1) }
            coords[2usize * s.x.len - 1usize - i] = Coord { x: x, y: baseline_y }
            i += 1usize
        }
        coord_count = 2usize * s.x.len
    } else if s.kind == .Lollipop {
        if coords.len < s.x.len || segments.len < s.x.len { ret (zero, TooLarge) }
        let baseline_y = y_position(s, s.baseline, y0, y1)
        while coord_count < s.x.len {
            let p = Coord { x: x_position(s, s.x[coord_count], xmin, xmax), y: y_position(s, s.y[coord_count], y0, y1) }
            coords[coord_count] = p
            segments[coord_count] = Segment { from: Coord { x: p.x, y: baseline_y }, to: p }
            coord_count += 1usize
        }
        segment_count = s.x.len
    } else if s.kind == .Step {
        if s.x.len > 1usize && segments.len / 2usize < s.x.len - 1usize { ret (zero, TooLarge) }
        var i = 0usize
        while i + 1usize < s.x.len {
            if s.x[i + 1usize] < s.x[i] { ret (zero, Invalid) }
            let left = Coord {
                x: x_position(s, s.x[i], xmin, xmax),
                y: y_position(s, s.y[i], y0, y1),
            }
            let right = Coord {
                x: x_position(s, s.x[i + 1usize], xmin, xmax),
                y: left.y,
            }
            let next = Coord {
                x: right.x,
                y: y_position(s, s.y[i + 1usize], y0, y1),
            }
            segments[segment_count] = Segment { from: left, to: right }
            segments[segment_count + 1usize] = Segment { from: right, to: next }
            segment_count += 2usize
            i += 1usize
        }
    } else {
        if bars.len < s.x.len { ret (zero, TooLarge) }
        var width = s.bar_width
        if width <= 0.0 { width = s.bounds.width / f32(i64(s.x.len)) * 0.8 }
        if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
        while bar_count < s.x.len {
            let cx = x_position(s, s.x[bar_count], xmin, xmax)
            var top_value = s.baseline
            if s.y[bar_count] > top_value { top_value = s.y[bar_count] }
            var bottom_value = s.baseline
            if s.y[bar_count] < bottom_value { bottom_value = s.y[bar_count] }
            var top = y_position(s, top_value, y0, y1)
            var bottom = y_position(s, bottom_value, y0, y1)
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[bar_count] = geometry.rect(cx - width / 2.0, top, width, bottom - top)
            bar_count += 1usize
        }
    }
    ret (Layout { kind: s.kind, coords: coords[..coord_count], segments: segments[..segment_count], bars: bars[..bar_count], x_min: xmin, x_max: xmax, y_min: y0, y_max: y1 }, ok)
}

// Size encodes circle area, not diameter. Zero-sized observations stay in the
// borrowed data but emit no visible mark; x/y use the ordinary scatter scales.
fn bubble(s: *const Spec, sizes: []const f32, max_radius: f32, coords: []Coord, circles: []geometry.Rect) -> (Layout, err) {
    if s.kind != .Bubble || sizes.len != s.x.len || sizes.len != s.y.len { ret (zero, Invalid) }
    if sizes.len == 0usize { ret (zero, Empty) }
    if !finite(max_radius) || max_radius <= 0.0 || !finite(max_radius * 2.0) { ret (zero, Invalid) }
    if circles.len < sizes.len { ret (zero, TooLarge) }
    var maximum = 0.0f32
    var i = 0usize
    while i < sizes.len {
        if !finite(sizes[i]) || sizes[i] < 0.0 { ret (zero, Invalid) }
        if sizes[i] > maximum { maximum = sizes[i] }
        i += 1usize
    }
    if maximum == 0.0 { ret (zero, Invalid) }
    var dots = *s
    dots.kind = .Scatter
    let (positions, positions_error) = layout(&dots, coords, zero, circles[..0usize])
    if positions_error != ok { ret (zero, positions_error) }
    i = 0usize
    while i < sizes.len {
        let radius = max_radius * f32(math.sqrt[f64](f64(sizes[i]) / f64(maximum)))
        let center = positions.coords[i]
        if !finite(center.x) || !finite(center.y) || !finite(center.x - radius) || !finite(center.y - radius) { ret (zero, Invalid) }
        circles[i] = geometry.rect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)
        i += 1usize
    }
    ret (Layout { kind: .Bubble, coords: positions.coords, segments: zero, bars: circles[..sizes.len], x_min: positions.x_min, x_max: positions.x_max, y_min: positions.y_min, y_max: positions.y_max }, ok)
}

// One-predictor OLS influence map: leverage x internally standardized
// residual, with bubble *area* proportional to Cook's distance. Reference
// lines at +/-2 and 2x/3x mean leverage are visual guides, not tests.
fn influence_plot(diagnostics: []const stat.RegressionDiagnostic, bounds: geometry.Rect, max_radius: f32, points: []Coord, circles: []geometry.Rect, reference_lines: []Segment) -> (InfluenceLayout, err) {
    if diagnostics.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(max_radius) || max_radius <= 0.0 || !finite(max_radius * 2.0) { ret (zero, Invalid) }
    if points.len < diagnostics.len || circles.len < diagnostics.len || reference_lines.len < 5usize { ret (zero, TooLarge) }
    var max_leverage = 0.0f64
    var max_abs_residual = 2.0f64
    var max_cook = 0.0f64
    var i = 0usize
    while i < diagnostics.len {
        let entry = diagnostics[i]
        if !finite64(entry.leverage) || !finite64(entry.standardized) || !finite64(entry.cook) || entry.leverage < 0.0f64 || entry.leverage >= 1.0f64 || entry.cook < 0.0f64 { ret (zero, Invalid) }
        if entry.leverage > max_leverage { max_leverage = entry.leverage }
        if entry.standardized > max_abs_residual { max_abs_residual = entry.standardized }
        if 0.0f64 - entry.standardized > max_abs_residual { max_abs_residual = 0.0f64 - entry.standardized }
        if entry.cook > max_cook { max_cook = entry.cook }
        i += 1usize
    }
    if max_cook <= 0.0f64 { ret (zero, Invalid) }
    var leverage_guide = 6.0f64 / f64(diagnostics.len)
    if leverage_guide > 1.0f64 { leverage_guide = 1.0f64 }
    if leverage_guide > max_leverage { max_leverage = leverage_guide }
    let xmax = max_leverage * 1.08f64
    let yabs = max_abs_residual * 1.10f64
    if !finite64(xmax) || !finite64(yabs) || !finite(f32(xmax)) || !finite(f32(yabs)) { ret (zero, Invalid) }
    i = 0usize
    while i < diagnostics.len {
        let entry = diagnostics[i]
        let px = bounds.x + bounds.width * f32(entry.leverage / xmax)
        let py = bounds.y + bounds.height * f32((yabs - entry.standardized) / (2.0f64 * yabs))
        let radius = max_radius * f32(math.sqrt[f64](entry.cook / max_cook))
        if !finite(px) || !finite(py) || !finite(radius) || !finite(px - radius) || !finite(py - radius) { ret (zero, Invalid) }
        points[i] = Coord { x: px, y: py }
        circles[i] = geometry.rect(px - radius, py - radius, radius * 2.0, radius * 2.0)
        i += 1usize
    }
    var used = 0usize
    let levels = [3]f64{ -2.0f64, 0.0f64, 2.0f64 }
    i = 0usize
    while i < levels.len {
        let py = bounds.y + bounds.height * f32((yabs - levels[i]) / (2.0f64 * yabs))
        reference_lines[used] = Segment { from: Coord { x: bounds.x, y: py }, to: Coord { x: bounds.x + bounds.width, y: py } }
        used += 1usize
        i += 1usize
    }
    let multipliers = [2]f64{ 4.0f64, 6.0f64 }
    i = 0usize
    while i < multipliers.len {
        let threshold = multipliers[i] / f64(diagnostics.len)
        if threshold <= 1.0f64 {
            let px = bounds.x + bounds.width * f32(threshold / xmax)
            reference_lines[used] = Segment { from: Coord { x: px, y: bounds.y }, to: Coord { x: px, y: bounds.y + bounds.height } }
            used += 1usize
        }
        i += 1usize
    }
    let dots = Layout { kind: .Scatter, coords: points[..diagnostics.len], segments: zero, bars: zero, x_min: 0.0, x_max: f32(xmax), y_min: 0.0 - f32(yabs), y_max: f32(yabs) }
    let bubbles = Layout { kind: .Bubble, coords: points[..diagnostics.len], segments: zero, bars: circles[..diagnostics.len], x_min: 0.0, x_max: f32(xmax), y_min: 0.0 - f32(yabs), y_max: f32(yabs) }
    let guides = Layout { kind: .Rug, coords: zero, segments: reference_lines[..used], bars: zero, x_min: 0.0, x_max: f32(xmax), y_min: 0.0 - f32(yabs), y_max: f32(yabs) }
    ret (InfluenceLayout { points: dots, bubbles: bubbles, guides: guides, max_cook: max_cook }, ok)
}

type PairedStats = struct { summary: stat.Regression, x_min: f32, x_max: f32, y_min: f32, y_max: f32 }

fn paired_stats(x: []const f32, y: []const f32) -> (PairedStats, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len { ret (zero, Invalid) }
    var result = PairedStats { summary: stat.regression(), x_min: x[0usize], x_max: x[0usize], y_min: y[0usize], y_max: y[0usize] }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(y[i]) { ret (zero, Invalid) }
        stat.regression_add(&result.summary, f64(x[i]), f64(y[i]))
        if x[i] < result.x_min { result.x_min = x[i] }
        if x[i] > result.x_max { result.x_max = x[i] }
        if y[i] < result.y_min { result.y_min = y[i] }
        if y[i] > result.y_max { result.y_max = y[i] }
        i += 1usize
    }
    ret (result, ok)
}

// Ordinary least squares in data space. The returned domain includes fitted
// endpoints so a caller can map scatter marks with the same explicit limits.
fn regression_line(x: []const f32, y: []const f32, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if segments.len == 0usize { ret (zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, data_error) }
    let (slope, has_slope) = stat.regression_slope(&data.summary)
    let (intercept, has_intercept) = stat.regression_intercept(&data.summary)
    if !has_slope || !has_intercept || !finite64(slope) || !finite64(intercept) { ret (zero, Invalid) }
    let first_y = f32(slope * f64(data.x_min) + intercept)
    let last_y = f32(slope * f64(data.x_max) + intercept)
    if !finite(first_y) || !finite(last_y) { ret (zero, Invalid) }
    var low = data.y_min
    var high = data.y_max
    if first_y < low { low = first_y }
    if last_y < low { low = last_y }
    if first_y > high { high = first_y }
    if last_y > high { high = last_y }
    if low == high {
        low -= 0.5
        high += 0.5
    }
    let line_x = [2]f32{ data.x_min, data.x_max }
    let line_y = [2]f32{ first_y, last_y }
    let y_limits = [2]f32{ low, high }
    var line_spec = spec(.Line, bounds, line_x[..], line_y[..])
    let (marks, marks_error) = layout_with_limits(&line_spec, zero, segments, zero, line_x[..], y_limits[..])
    ret (marks, marks_error)
}

// OLS mean-confidence or new-observation prediction ribbon. `critical` is
// the caller's two-sided Student-t quantile with count-2 degrees of freedom.
// Both layers share a domain that includes the observations and ribbon.
fn regression_interval(x: []const f32, y: []const f32, bounds: geometry.Rect, critical: f32, prediction: bool, outline: []Coord, fit: []Segment) -> (Layout, Layout, err) {
    if !valid_bounds(bounds) || !finite(critical) || critical <= 0.0 { ret (zero, zero, Invalid) }
    if outline.len < 4usize || outline.len % 2usize != 0usize || fit.len == 0usize { ret (zero, zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, zero, data_error) }
    let s = data.summary
    if s.count < 3u64 || s.m2_x <= 0.0f64 || data.x_min == data.x_max { ret (zero, zero, Invalid) }
    let slope = s.cov / s.m2_x
    let intercept = s.mean_y - slope * s.mean_x
    let residual = s.m2_y - slope * s.cov
    if !finite64(slope) || !finite64(intercept) || !finite64(residual) || residual < -0.0000000001f64 * (1.0f64 + s.m2_y) { ret (zero, zero, Invalid) }
    var nonnegative = residual
    if nonnegative < 0.0f64 { nonnegative = 0.0f64 }
    let sigma = math.sqrt[f64](nonnegative / f64(s.count - 2u64))
    let base = 1.0f64 / f64(s.count)
    var ymin = data.y_min
    var ymax = data.y_max
    let samples = outline.len / 2usize
    var i = 0usize
    while i < samples {
        let value_x = f64(data.x_min) + (f64(data.x_max) - f64(data.x_min)) * f64(i) / f64(samples - 1usize)
        let offset = value_x - s.mean_x
        var leverage = base + offset * offset / s.m2_x
        if prediction { leverage += 1.0f64 }
        let estimate = slope * value_x + intercept
        let half_width = f64(critical) * sigma * math.sqrt[f64](leverage)
        let lower = f32(estimate - half_width)
        let upper = f32(estimate + half_width)
        let position = f32(value_x)
        if !finite(lower) || !finite(upper) || !finite(position) { ret (zero, zero, Invalid) }
        outline[i] = Coord { x: position, y: upper }
        outline[2usize * samples - 1usize - i] = Coord { x: position, y: lower }
        if lower < ymin { ymin = lower }
        if upper > ymax { ymax = upper }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(ymin) || !finite(ymax) { ret (zero, zero, Invalid) }
    i = 0usize
    while i < outline.len {
        outline[i] = Coord { x: mapped(outline[i].x, data.x_min, data.x_max, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(outline[i].y, ymin, ymax, 0.0, bounds.height) }
        i += 1usize
    }
    let first = f32(slope * f64(data.x_min) + intercept)
    let last = f32(slope * f64(data.x_max) + intercept)
    if !finite(first) || !finite(last) { ret (zero, zero, Invalid) }
    fit[0usize] = Segment { from: Coord { x: bounds.x, y: bounds.y + bounds.height - mapped(first, ymin, ymax, 0.0, bounds.height) }, to: Coord { x: bounds.x + bounds.width, y: bounds.y + bounds.height - mapped(last, ymin, ymax, 0.0, bounds.height) } }
    let ribbon = Layout { kind: .Band, coords: outline, segments: zero, bars: zero, x_min: data.x_min, x_max: data.x_max, y_min: ymin, y_max: ymax }
    let line = Layout { kind: .Line, coords: zero, segments: fit[..1usize], bars: zero, x_min: data.x_min, x_max: data.x_max, y_min: ymin, y_max: ymax }
    ret (ribbon, line, ok)
}

// Covariance contour at a caller-selected Mahalanobis radius. A 95% contour
// for bivariate normal data uses radius sqrt(chi-square(2, .95)) ~= 2.4477.
fn covariance_ellipse(x: []const f32, y: []const f32, bounds: geometry.Rect, radius: f32, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(radius) || radius <= 0.0 { ret (zero, Invalid) }
    if segments.len < 8usize { ret (zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, data_error) }
    if data.summary.count < 3u64 { ret (zero, Invalid) }
    let denominator = f64(data.summary.count - 1u64)
    let variance_x = data.summary.m2_x / denominator
    let variance_y = data.summary.m2_y / denominator
    let covariance = data.summary.cov / denominator
    if !finite64(variance_x) || !finite64(variance_y) || !finite64(covariance) || variance_x <= 0.0f64 || variance_y <= 0.0f64 { ret (zero, Invalid) }
    let spread_x = math.sqrt[f64](variance_x)
    let tilt = covariance / spread_x
    let remainder = variance_y - tilt * tilt
    if !finite64(remainder) || remainder <= 0.0f64 { ret (zero, Invalid) }
    let spread_y = math.sqrt[f64](remainder)
    let reach_x = f64(radius) * spread_x
    let reach_y = f64(radius) * math.sqrt[f64](variance_y)
    var xmin = data.x_min
    var xmax = data.x_max
    var ymin = data.y_min
    var ymax = data.y_max
    let left = f32(data.summary.mean_x - reach_x)
    let right = f32(data.summary.mean_x + reach_x)
    let bottom = f32(data.summary.mean_y - reach_y)
    let top = f32(data.summary.mean_y + reach_y)
    if !finite(left) || !finite(right) || !finite(bottom) || !finite(top) { ret (zero, Invalid) }
    if left < xmin { xmin = left }
    if right > xmax { xmax = right }
    if bottom < ymin { ymin = bottom }
    if top > ymax { ymax = top }
    let dx = f64(xmax) - f64(xmin)
    let dy = f64(ymax) - f64(ymin)
    if dx <= 0.0f64 || dy <= 0.0f64 { ret (zero, Invalid) }
    let first_data_x = data.summary.mean_x + f64(radius) * spread_x
    let first_data_y = data.summary.mean_y + f64(radius) * tilt
    let first = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (first_data_x - f64(xmin)) / dx), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (first_data_y - f64(ymin)) / dy)) }
    if !finite(first.x) || !finite(first.y) { ret (zero, Invalid) }
    var previous = first
    var i = 0usize
    while i < segments.len {
        var next = first
        if i + 1usize < segments.len {
            let angle = 6.283185307179586f64 * f64(i + 1usize) / f64(segments.len)
            let cosine = math.cos[f64](angle)
            let sine = math.sin[f64](angle)
            let value_x = data.summary.mean_x + f64(radius) * spread_x * cosine
            let value_y = data.summary.mean_y + f64(radius) * (tilt * cosine + spread_y * sine)
            next = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (value_x - f64(xmin)) / dx), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (value_y - f64(ymin)) / dy)) }
            if !finite(next.x) || !finite(next.y) { ret (zero, Invalid) }
        }
        segments[i] = Segment { from: previous, to: next }
        previous = next
        i += 1usize
    }
    ret (Layout { kind: .Line, coords: zero, segments: segments, bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// Vertical intervals with a point estimate and two caps per observation.
// Lower/upper values must enclose each estimate; all output is caller-owned.
fn error_bars(x: []const f32, center: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, points: []Coord, lines: []Segment) -> (Layout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if center.len != x.len || lower.len != x.len || upper.len != x.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < x.len || lines.len / 3usize < x.len { ret (zero, TooLarge) }
    let (raw_xmin, raw_xmax, x_error) = extent(x)
    if x_error != ok { ret (zero, x_error) }
    var ymin = lower[0usize]
    var ymax = upper[0usize]
    var i = 0usize
    while i < x.len {
        if !finite(center[i]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > center[i] || center[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < ymin { ymin = lower[i] }
        if upper[i] > ymax { ymax = upper[i] }
        i += 1usize
    }
    var xmin = raw_xmin
    var xmax = raw_xmax
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    i = 0usize
    while i < x.len {
        let px = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let top = bounds.y + bounds.height - mapped(upper[i], ymin, ymax, 0.0, bounds.height)
        let bottom = bounds.y + bounds.height - mapped(lower[i], ymin, ymax, 0.0, bounds.height)
        let middle = bounds.y + bounds.height - mapped(center[i], ymin, ymax, 0.0, bounds.height)
        points[i] = Coord { x: px, y: middle }
        lines[3usize * i] = Segment { from: Coord { x: px, y: top }, to: Coord { x: px, y: bottom } }
        lines[3usize * i + 1usize] = Segment { from: Coord { x: px - 5.0, y: top }, to: Coord { x: px + 5.0, y: top } }
        lines[3usize * i + 2usize] = Segment { from: Coord { x: px - 5.0, y: bottom }, to: Coord { x: px + 5.0, y: bottom } }
        i += 1usize
    }
    ret (Layout { kind: .ErrorBar, coords: points[..x.len], segments: lines[..3usize * x.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// A closed ribbon between lower and upper series. Ordered x and contained
// intervals are required; the polygon remains in caller-provided storage.
fn band(x: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, outline: []Coord) -> (Layout, err) {
    if x.len < 2usize { ret (zero, Empty) }
    if lower.len != x.len || upper.len != x.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if outline.len / 2usize < x.len { ret (zero, TooLarge) }
    let (xmin, xmax, x_error) = extent(x)
    if x_error != ok { ret (zero, x_error) }
    if xmin == xmax { ret (zero, Invalid) }
    var ymin = lower[0usize]
    var ymax = upper[0usize]
    var i = 0usize
    while i < x.len {
        if (i > 0usize && x[i] < x[i - 1usize]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < ymin { ymin = lower[i] }
        if upper[i] > ymax { ymax = upper[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(ymin) || !finite(ymax) { ret (zero, Invalid) }
    i = 0usize
    while i < x.len {
        let px = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        outline[i] = Coord { x: px, y: bounds.y + bounds.height - mapped(upper[i], ymin, ymax, 0.0, bounds.height) }
        outline[2usize * x.len - 1usize - i] = Coord { x: px, y: bounds.y + bounds.height - mapped(lower[i], ymin, ymax, 0.0, bounds.height) }
        i += 1usize
    }
    ret (Layout { kind: .Band, coords: outline[..2usize * x.len], segments: zero, bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// Band-major outer-to-inner forecast intervals share one domain and a median Line.
fn fan(x: []const f32, median: []const f32, lower: []const f32, upper: []const f32, bands: usize, bounds: geometry.Rect, outlines: []Coord, median_segments: []Segment, layers: []Layout) -> ([]Layout, Layout, err) {
    if x.len < 2usize { ret (zero, zero, Empty) }
    if bands == 0usize { ret (zero, zero, Invalid) }
    if median.len != x.len || lower.len != upper.len || lower.len / x.len != bands || lower.len % x.len != 0usize || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if outlines.len / x.len / 2usize < bands || median_segments.len < x.len - 1usize || layers.len < bands { ret (zero, zero, TooLarge) }
    var ymin = f64(lower[0usize])
    var ymax = f64(upper[0usize])
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(median[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, zero, Invalid) }
        var band_index = 0usize
        while band_index < bands {
            let at = band_index * x.len + i
            let lo = lower[at]
            let hi = upper[at]
            if !finite(lo) || !finite(hi) || lo > median[i] || median[i] > hi { ret (zero, zero, Invalid) }
            if band_index > 0usize && (lo < lower[at - x.len] || hi > upper[at - x.len]) { ret (zero, zero, Invalid) }
            band_index += 1usize
        }
        if f64(lower[i]) < ymin { ymin = f64(lower[i]) }
        if f64(upper[i]) > ymax { ymax = f64(upper[i]) }
        i += 1usize
    }
    let raw_min = f32(ymin)
    let raw_max = f32(ymax)
    if ymin == ymax {
        ymin -= 1.0f64
        ymax += 1.0f64
    }
    let x_span = f64(x[x.len - 1usize]) - f64(x[0usize])
    var band_index = 0usize
    while band_index < bands {
        let first = band_index * 2usize * x.len
        i = 0usize
        while i < x.len {
            let px = f32(f64(bounds.x) + f64(bounds.width) * (f64(x[i]) - f64(x[0usize])) / x_span)
            let top = f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(upper[band_index * x.len + i]) - ymin) / (ymax - ymin)))
            let bottom = f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(lower[band_index * x.len + i]) - ymin) / (ymax - ymin)))
            if !finite(px) || !finite(top) || !finite(bottom) { ret (zero, zero, Invalid) }
            outlines[first + i] = Coord { x: px, y: top }
            outlines[first + 2usize * x.len - 1usize - i] = Coord { x: px, y: bottom }
            i += 1usize
        }
        layers[band_index] = Layout { kind: .Band, coords: outlines[first..first + 2usize * x.len], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: raw_min, y_max: raw_max }
        band_index += 1usize
    }
    i = 0usize
    while i + 1usize < x.len {
        let left = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (f64(x[i]) - f64(x[0usize])) / x_span), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(median[i]) - ymin) / (ymax - ymin))) }
        let right = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (f64(x[i + 1usize]) - f64(x[0usize])) / x_span), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(median[i + 1usize]) - ymin) / (ymax - ymin))) }
        if !finite(left.x) || !finite(left.y) || !finite(right.x) || !finite(right.y) { ret (zero, zero, Invalid) }
        median_segments[i] = Segment { from: left, to: right }
        i += 1usize
    }
    ret (layers[..bands], Layout { kind: .Line, coords: zero, segments: median_segments[..x.len - 1usize], bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: raw_min, y_max: raw_max }, ok)
}

// Centered stacked areas share one y scale and one caller-owned polygon per series.
// Values are sample-major: every x position carries all series in input order.
// ponytail: silhouette centering is stable; add wiggle offsets if trend-heavy data needs them.
fn streamgraph(x: []const f32, values: []const f32, series: usize, bounds: geometry.Rect, totals: []f64, cumulative: []f64, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if x.len < 2usize || series == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || values.len / x.len != series || values.len % x.len != 0usize { ret (zero, Invalid) }
    if totals.len < x.len || cumulative.len < x.len || outline.len / x.len / 2usize < series || layers.len < series { ret (zero, TooLarge) }
    var max_total = 0.0f64
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, Invalid) }
        var total = 0.0f64
        var j = 0usize
        while j < series {
            let value = values[i * series + j]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            total += f64(value)
            j += 1usize
        }
        if !finite(f32(total)) { ret (zero, Invalid) }
        totals[i] = total
        if total > max_total { max_total = total }
        i += 1usize
    }
    if max_total <= 0.0f64 { ret (zero, Empty) }
    i = 0usize
    while i < x.len {
        cumulative[i] = (max_total - totals[i]) * 0.5f64
        i += 1usize
    }
    var layer = 0usize
    while layer < series {
        let first = layer * 2usize * x.len
        i = 0usize
        while i < x.len {
            let lower = cumulative[i]
            let upper = lower + f64(values[i * series + layer])
            let px = bounds.x + bounds.width * f32((f64(x[i]) - f64(x[0usize])) / (f64(x[x.len - 1usize]) - f64(x[0usize])))
            let top = bounds.y + bounds.height * (1.0 - f32(upper / max_total))
            let bottom = bounds.y + bounds.height * (1.0 - f32(lower / max_total))
            if !finite(px) || !finite(top) || !finite(bottom) { ret (zero, Invalid) }
            outline[first + i] = Coord { x: px, y: top }
            outline[first + 2usize * x.len - 1usize - i] = Coord { x: px, y: bottom }
            cumulative[i] = upper
            i += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: outline[first..first + 2usize * x.len], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: 0.0, y_max: f32(max_total) }
        layer += 1usize
    }
    ret (layers[..series], ok)
}

// Equal-height rank bands over increasing x positions. Values are sample-major;
// higher values rank first, and ties keep the original series order.
// ponytail: O(samples * series^2) comparisons; sort per sample if large series counts matter.
fn ribbon_rank(x: []const f32, values: []const f32, series: usize, bounds: geometry.Rect, gap: f32, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if x.len < 2usize || series == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(gap) || gap < 0.0 || values.len / x.len != series || values.len % x.len != 0usize { ret (zero, Invalid) }
    if outline.len / x.len / 2usize < series || layers.len < series { ret (zero, TooLarge) }
    let total_gap = gap * f32(series - 1usize)
    if !finite(total_gap) || total_gap >= bounds.height { ret (zero, Invalid) }
    let band_height = (bounds.height - total_gap) / f32(series)
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, Invalid) }
        var j = 0usize
        while j < series {
            if !finite(values[i * series + j]) { ret (zero, Invalid) }
            j += 1usize
        }
        i += 1usize
    }
    var layer = 0usize
    while layer < series {
        let first = layer * 2usize * x.len
        i = 0usize
        while i < x.len {
            let value = values[i * series + layer]
            var rank = 0usize
            var other = 0usize
            while other < series {
                let candidate = values[i * series + other]
                if candidate > value || (candidate == value && other < layer) { rank += 1usize }
                other += 1usize
            }
            let px = bounds.x + bounds.width * f32((f64(x[i]) - f64(x[0usize])) / (f64(x[x.len - 1usize]) - f64(x[0usize])))
            let top = bounds.y + f32(rank) * (band_height + gap)
            let bottom = top + band_height
            if !finite(px) || !finite(top) || !finite(bottom) { ret (zero, Invalid) }
            outline[first + i] = Coord { x: px, y: top }
            outline[first + 2usize * x.len - 1usize - i] = Coord { x: px, y: bottom }
            i += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: outline[first..first + 2usize * x.len], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: 0.0, y_max: f32(series) }
        layer += 1usize
    }
    ret (layers[..series], ok)
}

// Horizontal intervals with a dot at each endpoint; `position` is the
// numeric vertical axis, so repeated positions naturally overlay.
fn dumbbell(position: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, points: []Coord, lines: []Segment) -> (Layout, err) {
    if position.len == 0usize { ret (zero, Empty) }
    if lower.len != position.len || upper.len != position.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len / 2usize < position.len || lines.len < position.len { ret (zero, TooLarge) }
    let (raw_ymin, raw_ymax, y_error) = extent(position)
    if y_error != ok { ret (zero, y_error) }
    var xmin = lower[0usize]
    var xmax = upper[0usize]
    var i = 0usize
    while i < position.len {
        if !finite(lower[i]) || !finite(upper[i]) || lower[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < xmin { xmin = lower[i] }
        if upper[i] > xmax { xmax = upper[i] }
        i += 1usize
    }
    var ymin = raw_ymin
    var ymax = raw_ymax
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(xmin) || !finite(xmax) || !finite(ymin) || !finite(ymax) { ret (zero, Invalid) }
    i = 0usize
    while i < position.len {
        let py = bounds.y + bounds.height - mapped(position[i], ymin, ymax, 0.0, bounds.height)
        let left = Coord { x: mapped(lower[i], xmin, xmax, bounds.x, bounds.width), y: py }
        let right = Coord { x: mapped(upper[i], xmin, xmax, bounds.x, bounds.width), y: py }
        points[2usize * i] = left
        points[2usize * i + 1usize] = right
        lines[i] = Segment { from: left, to: right }
        i += 1usize
    }
    ret (Layout { kind: .Dumbbell, coords: points[..2usize * position.len], segments: lines[..position.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// Paired values share one vertical scale; input order preserves series identity
// even when the segments cross. Coordinates are before/after pairs.
fn slopegraph(before: []const f32, after: []const f32, bounds: geometry.Rect, points: []Coord, lines: []Segment) -> (Layout, err) {
    if before.len == 0usize { ret (zero, Empty) }
    if before.len != after.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len / 2usize < before.len || lines.len < before.len { ret (zero, TooLarge) }
    var ymin = before[0usize]
    var ymax = before[0usize]
    var i = 0usize
    while i < before.len {
        if !finite(before[i]) || !finite(after[i]) { ret (zero, Invalid) }
        if before[i] < ymin { ymin = before[i] }
        if after[i] < ymin { ymin = after[i] }
        if before[i] > ymax { ymax = before[i] }
        if after[i] > ymax { ymax = after[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(ymin) || !finite(ymax) { ret (zero, Invalid) }
    i = 0usize
    while i < before.len {
        let left = Coord { x: bounds.x, y: bounds.y + bounds.height - mapped(before[i], ymin, ymax, 0.0, bounds.height) }
        let right = Coord { x: bounds.x + bounds.width, y: bounds.y + bounds.height - mapped(after[i], ymin, ymax, 0.0, bounds.height) }
        if !finite(left.y) || !finite(right.y) { ret (zero, Invalid) }
        points[2usize * i] = left
        points[2usize * i + 1usize] = right
        lines[i] = Segment { from: left, to: right }
        i += 1usize
    }
    ret (Layout { kind: .SlopeGraph, coords: points[..2usize * before.len], segments: lines[..before.len], bars: zero, x_min: 0.0, x_max: 1.0, y_min: ymin, y_max: ymax }, ok)
}

// Horizontal study intervals, center estimates and one reference rule.
fn forest_plot(estimate: []const f32, lower: []const f32, upper: []const f32, reference: f32, scale: Scale, bounds: geometry.Rect, points: []Coord, intervals: []Segment, reference_rule: []Segment) -> (Layout, Layout, err) {
    if estimate.len == 0usize { ret (zero, zero, Empty) }
    if lower.len != estimate.len || upper.len != estimate.len || !valid_bounds(bounds) || !finite(reference) { ret (zero, zero, Invalid) }
    if points.len < estimate.len || intervals.len < estimate.len || reference_rule.len == 0usize { ret (zero, zero, TooLarge) }
    var xmin = reference
    var xmax = reference
    var i = 0usize
    while i < estimate.len {
        if !finite(estimate[i]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > estimate[i] || estimate[i] > upper[i] { ret (zero, zero, Invalid) }
        if lower[i] < xmin { xmin = lower[i] }
        if upper[i] > xmax { xmax = upper[i] }
        i += 1usize
    }
    if xmin == xmax {
        if scale.kind == .Log10 {
            if xmin <= 0.0 { ret (zero, zero, Invalid) }
            xmin *= 0.5
            xmax *= 2.0
        } else {
            xmin -= 0.5
            xmax += 0.5
        }
    }
    if !valid_scale(scale, xmin, xmax) { ret (zero, zero, Invalid) }
    i = 0usize
    while i < estimate.len {
        let y = bounds.y + bounds.height * (f32(i) + 0.5) / f32(estimate.len)
        let left = bounds.x + bounds.width * fraction(lower[i], xmin, xmax, scale)
        let middle = bounds.x + bounds.width * fraction(estimate[i], xmin, xmax, scale)
        let right = bounds.x + bounds.width * fraction(upper[i], xmin, xmax, scale)
        if !finite(y) || !finite(left) || !finite(middle) || !finite(right) { ret (zero, zero, Invalid) }
        points[i] = Coord { x: middle, y: y }
        intervals[i] = Segment { from: Coord { x: left, y: y }, to: Coord { x: right, y: y } }
        i += 1usize
    }
    let reference_x = bounds.x + bounds.width * fraction(reference, xmin, xmax, scale)
    reference_rule[0usize] = Segment { from: Coord { x: reference_x, y: bounds.y }, to: Coord { x: reference_x, y: bounds.y + bounds.height } }
    let studies = Layout { kind: .Dumbbell, coords: points[..estimate.len], segments: intervals[..estimate.len], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(estimate.len) }
    let rule = Layout { kind: .Rug, coords: zero, segments: reference_rule[..1usize], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(estimate.len) }
    ret (studies, rule, ok)
}

// Means and differences are chart scratch; agreement limits come from e.algo.stat.
fn bland_altman(left: []const f64, right: []const f64, critical: f64, bounds: geometry.Rect, means: []f32, differences: []f32, points: []Coord, rules: []Segment) -> (Layout, Layout, err) {
    if left.len < 2usize { ret (zero, zero, Empty) }
    if right.len != left.len || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if means.len < left.len || differences.len < left.len || points.len < left.len || rules.len < 3usize { ret (zero, zero, TooLarge) }
    let (agreement, defined) = stat.agreement_limits(left, right, critical)
    if !defined || !finite(f32(agreement.lower)) || !finite(f32(agreement.bias)) || !finite(f32(agreement.upper)) { ret (zero, zero, Invalid) }
    var ymin = f32(agreement.lower)
    var ymax = f32(agreement.upper)
    var i = 0usize
    while i < left.len {
        means[i] = f32(left[i] * 0.5f64 + right[i] * 0.5f64)
        differences[i] = f32(left[i] - right[i])
        if !finite(means[i]) || !finite(differences[i]) { ret (zero, zero, Invalid) }
        if differences[i] < ymin { ymin = differences[i] }
        if differences[i] > ymax { ymax = differences[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    let y_limits = [2]f32{ ymin, ymax }
    let plot = spec(.Scatter, bounds, means[..left.len], differences[..left.len])
    var unused_segments: [1]Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let (dots, dots_error) = layout_with_limits(&plot, points, unused_segments[..0usize], unused_bars[..0usize], means[..0usize], y_limits[..])
    if dots_error != ok { ret (zero, zero, dots_error) }
    let levels = [3]f32{ f32(agreement.lower), f32(agreement.bias), f32(agreement.upper) }
    i = 0usize
    while i < 3usize {
        let y = y_position(&plot, levels[i], ymin, ymax)
        rules[i] = Segment { from: Coord { x: bounds.x, y: y }, to: Coord { x: bounds.x + bounds.width, y: y } }
        i += 1usize
    }
    let guides = Layout { kind: .Rug, coords: zero, segments: rules[..3usize], bars: zero, x_min: dots.x_min, x_max: dots.x_max, y_min: ymin, y_max: ymax }
    ret (dots, guides, ok)
}

fn bar_grid_ok(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect) -> bool {
    ret valid_bounds(bounds) && values.len / categories == series && values.len % categories == 0usize && finite(f32(categories))
}

// Series-major output lets each caller-owned layer be painted with its own
// colour by the existing Bar adapter; input observations are category-major.
fn bar_layers(categories: usize, series: usize, bars: []geometry.Rect, layers: []Layout, ymin: f32, ymax: f32) -> []Layout {
    var i = 0usize
    while i < series {
        let first = i * categories
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[first..first + categories], x_min: 0.0, x_max: f32(categories), y_min: ymin, y_max: ymax }
        i += 1usize
    }
    ret layers[..series]
}

// The first value is an absolute starting total; later values are signed
// changes. The final bar is the resulting total, with level connectors.
fn waterfall(values: []const f32, bounds: geometry.Rect, bars: []geometry.Rect, connectors: []Segment) -> (Layout, err) {
    if values.len < 2usize { ret (zero, Empty) }
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if bars.len <= values.len || connectors.len < values.len { ret (zero, TooLarge) }
    var low = 0.0f64
    var high = 0.0f64
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, Invalid) }
        let before = total
        if i == 0usize { total = f64(values[i]) } else { total += f64(values[i]) }
        if !finite(f32(total)) { ret (zero, Invalid) }
        if before < low { low = before }
        if before > high { high = before }
        if total < low { low = total }
        if total > high { high = total }
        i += 1usize
    }
    var ymin = f32(low)
    var ymax = f32(high)
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    let count = values.len + 1usize
    let cell = bounds.width / f32(count)
    let width = cell * 0.72
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    let offset = (cell - width) * 0.5
    total = 0.0f64
    i = 0usize
    while i < count {
        let before = total
        if i < values.len {
            if i == 0usize { total = f64(values[i]) } else { total += f64(values[i]) }
        }
        var from = f32(before)
        if i == 0usize || i == values.len { from = 0.0 }
        let y0 = bounds.y + bounds.height - mapped(from, ymin, ymax, 0.0, bounds.height)
        let y1 = bounds.y + bounds.height - mapped(f32(total), ymin, ymax, 0.0, bounds.height)
        var top = y0
        var bottom = y1
        if top > bottom {
            top = y1
            bottom = y0
        }
        let x = bounds.x + cell * f32(i) + offset
        bars[i] = geometry.rect(x, top, width, bottom - top)
        if i < values.len {
            let level = bounds.y + bounds.height - mapped(f32(total), ymin, ymax, 0.0, bounds.height)
            connectors[i] = Segment { from: Coord { x: x + width, y: level }, to: Coord { x: x + cell, y: level } }
        }
        i += 1usize
    }
    ret (Layout { kind: .Waterfall, coords: zero, segments: connectors[..values.len], bars: bars[..count], x_min: 0.0, x_max: f32(count), y_min: ymin, y_max: ymax }, ok)
}

// A one-basis, share-count cap table: existing holders, then optional pool
// top-up and new-investor issuance. The bridge tracks retained incumbent
// ownership from 100% through pool and financing dilution.
fn cap_table_waterfall(existing_shares: []const u64, pool_added: u64, investor_added: u64, before_bounds: geometry.Rect, after_bounds: geometry.Rect, bridge_bounds: geometry.Rect, work: *CapTableWork) -> (CapTableLayout, err) {
    let n = existing_shares.len
    if n == 0usize { ret (zero, Empty) }
    if pool_added == 0u64 && investor_added == 0u64 { ret (zero, Invalid) }
    if !valid_bounds(before_bounds) || !valid_bounds(after_bounds) || !valid_bounds(bridge_bounds) || !finite(before_bounds.x + before_bounds.width) || !finite(after_bounds.x + after_bounds.width) || !finite(bridge_bounds.x + bridge_bounds.width) || !finite(bridge_bounds.y + bridge_bounds.height) { ret (zero, Invalid) }
    if work.before_bars.len < n || work.after_bars.len < n + 2usize || work.before_layers.len < n || work.after_layers.len < n + 2usize || work.before_fractions.len < n || work.after_fractions.len < n || work.bridge_bars.len < 4usize || work.bridge_links.len < 3usize { ret (zero, TooLarge) }
    var before_total = 0u64
    var i = 0usize
    while i < n {
        if existing_shares[i] == 0u64 || existing_shares[i] > 18446744073709551615u64 - before_total { ret (zero, Invalid) }
        before_total += existing_shares[i]
        i += 1usize
    }
    if pool_added > 18446744073709551615u64 - before_total { ret (zero, Invalid) }
    let with_pool = before_total + pool_added
    if investor_added > 18446744073709551615u64 - with_pool { ret (zero, Invalid) }
    let after_total = with_pool + investor_added
    let after_pool_fraction = f64(before_total) / f64(with_pool)
    let after_fraction = f64(before_total) / f64(after_total)
    if !finite64(after_pool_fraction) || !finite64(after_fraction) || after_fraction <= 0.0f64 { ret (zero, Invalid) }
    var before_x = before_bounds.x
    var after_x = after_bounds.x
    i = 0usize
    while i < n {
        let before_fraction = f64(existing_shares[i]) / f64(before_total)
        let holder_after_fraction = f64(existing_shares[i]) / f64(after_total)
        var before_width = before_bounds.width * f32(before_fraction)
        if i == n - 1usize { before_width = before_bounds.x + before_bounds.width - before_x }
        let after_width = after_bounds.width * f32(holder_after_fraction)
        if !finite(before_width) || !finite(after_width) || before_width <= 0.0f32 || after_width <= 0.0f32 { ret (zero, TooLarge) }
        work.before_fractions[i] = before_fraction
        work.after_fractions[i] = holder_after_fraction
        work.before_bars[i] = geometry.rect(before_x, before_bounds.y, before_width, before_bounds.height)
        work.after_bars[i] = geometry.rect(after_x, after_bounds.y, after_width, after_bounds.height)
        work.before_layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.before_bars[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        work.after_layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.after_bars[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        before_x += before_width
        after_x += after_width
        i += 1usize
    }
    var after_count = n
    if pool_added > 0u64 {
        let width = after_bounds.width * f32(f64(pool_added) / f64(after_total))
        if !finite(width) || width <= 0.0f32 { ret (zero, TooLarge) }
        work.after_bars[after_count] = geometry.rect(after_x, after_bounds.y, width, after_bounds.height)
        work.after_layers[after_count] = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.after_bars[after_count..after_count + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        after_x += width
        after_count += 1usize
    }
    if investor_added > 0u64 {
        let width = after_bounds.x + after_bounds.width - after_x
        if !finite(width) || width <= 0.0f32 { ret (zero, TooLarge) }
        work.after_bars[after_count] = geometry.rect(after_x, after_bounds.y, width, after_bounds.height)
        work.after_layers[after_count] = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.after_bars[after_count..after_count + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        after_count += 1usize
    } else {
        let last = after_count - 1usize
        work.after_bars[last].width = after_bounds.x + after_bounds.width - work.after_bars[last].x
    }
    let bridge_values = [3]f32{ 1.0f32, f32(after_pool_fraction - 1.0f64), f32(after_fraction - after_pool_fraction) }
    let (bridge, bridge_error) = waterfall(bridge_values[..], bridge_bounds, work.bridge_bars, work.bridge_links)
    if bridge_error != ok { ret (zero, bridge_error) }
    ret (CapTableLayout {
        before: work.before_layers[..n], after: work.after_layers[..after_count], bridge: bridge,
        before_fractions: work.before_fractions[..n], after_fractions: work.after_fractions[..n],
        pool_present: pool_added > 0u64, investor_present: investor_added > 0u64,
        summary: CapTableSummary {
            before_shares: before_total, after_shares: after_total, pool_added: pool_added, investor_added: investor_added,
            incumbent_fraction: after_fraction, pool_fraction: f64(pool_added) / f64(after_total), investor_fraction: f64(investor_added) / f64(after_total),
        },
    }, ok)
}

// Each case is a one-at-a-time input perturbation with two modeled outputs.
// Descending output swing is stable on ties; the two scenario bars remain
// distinct even when low input produces the higher modeled result.
fn tornado_sensitivity(cases: []const TornadoCase, baseline: f64, bounds: geometry.Rect, order: []usize, low_bars: []geometry.Rect, high_bars: []geometry.Rect, baseline_line: []Segment) -> (TornadoLayout, err) {
    let n = cases.len
    if n == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite64(baseline) { ret (zero, Invalid) }
    if order.len < n || low_bars.len < n || high_bars.len < n || baseline_line.len < 1usize { ret (zero, TooLarge) }
    var minimum = baseline
    var maximum = baseline
    var i = 0usize
    while i < n {
        let item = cases[i]
        if !finite64(item.low_result) || !finite64(item.high_result) { ret (zero, Invalid) }
        if item.low_result < minimum { minimum = item.low_result }
        if item.high_result < minimum { minimum = item.high_result }
        if item.low_result > maximum { maximum = item.low_result }
        if item.high_result > maximum { maximum = item.high_result }
        order[i] = i
        i += 1usize
    }
    let span = maximum - minimum
    if !finite64(span) || span <= 0.0f64 || !finite(f32(minimum)) || !finite(f32(maximum)) || f32(minimum) == f32(maximum) { ret (zero, Invalid) }
    // ponytail: insertion sort is quadratic; very wide sensitivity sets need caller-scratch mergesort.
    i = 1usize
    while i < n {
        let selected = order[i]
        var j = i
        var selected_swing = cases[selected].high_result - cases[selected].low_result
        if selected_swing < 0.0f64 { selected_swing = 0.0f64 - selected_swing }
        while j > 0usize {
            var previous_swing = cases[order[j - 1usize]].high_result - cases[order[j - 1usize]].low_result
            if previous_swing < 0.0f64 { previous_swing = 0.0f64 - previous_swing }
            if previous_swing >= selected_swing { break }
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = selected
        i += 1usize
    }
    let row_height = bounds.height / f32(n)
    if !finite(row_height) || row_height <= 0.0f32 { ret (zero, Invalid) }
    let base_x = bounds.x + bounds.width * f32((baseline - minimum) / span)
    if !finite(base_x) { ret (zero, Invalid) }
    i = 0usize
    while i < n {
        let item = cases[order[i]]
        let low_x = bounds.x + bounds.width * f32((item.low_result - minimum) / span)
        let high_x = bounds.x + bounds.width * f32((item.high_result - minimum) / span)
        if !finite(low_x) || !finite(high_x) { ret (zero, Invalid) }
        var low_left = base_x
        var low_width = low_x - base_x
        if low_width < 0.0f32 {
            low_left = low_x
            low_width = 0.0f32 - low_width
        }
        var high_left = base_x
        var high_width = high_x - base_x
        if high_width < 0.0f32 {
            high_left = high_x
            high_width = 0.0f32 - high_width
        }
        let y = bounds.y + f32(i) * row_height
        low_bars[i] = geometry.rect(low_left, y + row_height * 0.17f32, low_width, row_height * 0.29f32)
        high_bars[i] = geometry.rect(high_left, y + row_height * 0.54f32, high_width, row_height * 0.29f32)
        i += 1usize
    }
    baseline_line[0usize] = Segment { from: Coord { x: base_x, y: bounds.y }, to: Coord { x: base_x, y: bounds.y + bounds.height } }
    let low = Layout { kind: .Bar, coords: zero, segments: zero, bars: low_bars[..n], x_min: f32(minimum), x_max: f32(maximum), y_min: 0.0f32, y_max: f32(n) }
    let high = Layout { kind: .Bar, coords: zero, segments: zero, bars: high_bars[..n], x_min: f32(minimum), x_max: f32(maximum), y_min: 0.0f32, y_max: f32(n) }
    let guide = Layout { kind: .Rug, coords: zero, segments: baseline_line[..1usize], bars: zero, x_min: f32(minimum), x_max: f32(maximum), y_min: 0.0f32, y_max: f32(n) }
    ret (TornadoLayout { low: low, high: high, baseline: guide, order: order[..n], minimum: minimum, maximum: maximum }, ok)
}

// Qualitative ranges paint widest to narrowest, then actual and target.
// The caller chooses one brush per layer; no new painter is needed.
fn bullet(actual: f32, target_value: f32, ranges: []const f32, bounds: geometry.Rect, bars: []geometry.Rect, target_line: []Segment, layers: []Layout) -> ([]Layout, err) {
    if ranges.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(actual) || !finite(target_value) { ret (zero, Invalid) }
    if bars.len <= ranges.len || target_line.len == 0usize || layers.len < 2usize || layers.len - 2usize < ranges.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < ranges.len {
        if !finite(ranges[i]) || ranges[i] <= 0.0 || (i > 0usize && ranges[i] <= ranges[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let maximum = ranges[ranges.len - 1usize]
    if actual < 0.0 || actual > maximum || target_value < 0.0 || target_value > maximum { ret (zero, Invalid) }
    i = 0usize
    while i < ranges.len {
        let endpoint = ranges[ranges.len - 1usize - i]
        bars[i] = geometry.rect(bounds.x, bounds.y, bounds.width * (endpoint / maximum), bounds.height)
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[i..i + 1usize], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    bars[i] = geometry.rect(bounds.x, bounds.y + bounds.height * 0.325, bounds.width * (actual / maximum), bounds.height * 0.35)
    layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[i..i + 1usize], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    let x = bounds.x + bounds.width * (target_value / maximum)
    target_line[0usize] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
    layers[i + 1usize] = Layout { kind: .Rug, coords: zero, segments: target_line[..1usize], bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    ret (layers[..ranges.len + 2usize], ok)
}

// Signed delta is actual minus target; callers choose whether higher is better.
fn target_status(actual: f32, target_value: f32, higher_is_better: bool) -> (TargetStatus, err) {
    if !finite(actual) || !finite(target_value) { ret (zero, Invalid) }
    let delta = actual - target_value
    if !finite(delta) { ret (zero, Invalid) }
    var achieved = actual >= target_value
    if !higher_is_better { achieved = actual <= target_value }
    ret (TargetStatus { delta: delta, achieved: achieved }, ok)
}

// Descending frequency bars and a cumulative fraction line share category
// centres. `order` maps rendered positions back to the borrowed input.
fn pareto(values: []const f32, bounds: geometry.Rect, order: []usize, bars: []geometry.Rect, points: []Coord, lines: []Segment, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if order.len < values.len || bars.len < values.len || points.len < values.len || (values.len > 1usize && lines.len < values.len - 1usize) || layers.len < 2usize { ret (zero, TooLarge) }
    var total = 0.0f64
    var maximum = 0.0f32
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        if values[i] > maximum { maximum = values[i] }
        order[i] = i
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    // ponytail: insertion sort is quadratic; use caller-scratch mergesort for very wide category sets.
    i = 1usize
    while i < values.len {
        let selected = order[i]
        var j = i
        while j > 0usize && values[order[j - 1usize]] < values[selected] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = selected
        i += 1usize
    }
    let cell = bounds.width / f32(values.len)
    let width = cell * 0.8
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let value = values[order[i]]
        cumulative += f64(value)
        let x = bounds.x + cell * f32(i)
        let height = bounds.height * (value / maximum)
        bars[i] = geometry.rect(x + cell * 0.1, bounds.y + bounds.height - height, width, height)
        points[i] = Coord { x: x + cell * 0.5, y: bounds.y + bounds.height * (1.0 - f32(cumulative / total)) }
        if i > 0usize { lines[i - 1usize] = Segment { from: points[i - 1usize], to: points[i] } }
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..values.len], x_min: 0.0, x_max: f32(values.len), y_min: 0.0, y_max: maximum }
    layers[1usize] = Layout { kind: .PointLine, coords: points[..values.len], segments: lines[..values.len - 1usize], bars: zero, x_min: 0.0, x_max: f32(values.len), y_min: 0.0, y_max: 1.0 }
    ret (layers[..2usize], ok)
}

// Category-centred columns and a line share x while retaining independent
// vertical domains. The caller owns category positions and both mark layers.
fn combo_bar_line(columns: []const f32, line: []const f32, bounds: geometry.Rect, category_x: []f32, bars: []geometry.Rect, points: []Coord, segments: []Segment, layers: []Layout) -> ([]Layout, err) {
    if columns.len == 0usize { ret (zero, Empty) }
    if columns.len != line.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if category_x.len < columns.len || bars.len < columns.len || points.len < line.len || (line.len > 1usize && segments.len < line.len - 1usize) || layers.len < 2usize { ret (zero, TooLarge) }
    // ponytail: f32 centres need distinct integers; wider categories need a non-f32 axis.
    if columns.len >= 16777216usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < columns.len {
        category_x[i] = f32(i) + 0.5
        i += 1usize
    }
    let limits = [2]f32{ 0.0, f32(columns.len) }
    var column_spec = spec(.Bar, bounds, category_x[..columns.len], columns)
    let (column_layer, column_error) = layout_with_limits(&column_spec, zero, zero, bars, limits[..], zero)
    if column_error != ok { ret (zero, column_error) }
    var line_spec = spec(.PointLine, bounds, category_x[..line.len], line)
    let (line_layer, line_error) = layout_with_limits(&line_spec, points, segments, zero, limits[..], zero)
    if line_error != ok { ret (zero, line_error) }
    layers[0usize] = column_layer
    layers[1usize] = line_layer
    ret (layers[..2usize], ok)
}

// Each slice is a filled polygon; hole=0 gives a pie, 0<hole<1 a donut.
// A fixed full-circle tessellation keeps the painter and SVG paths identical.
fn pie(values: []const f32, bounds: geometry.Rect, hole: f32, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    if layers.len < values.len { ret (zero, TooLarge) }
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    var needed = 0usize
    i = 0usize
    while i < values.len {
        let steps = 2usize + usize(f64(values[i]) / total * 96.0f64)
        let count = 2usize * (steps + 1usize)
        if needed > points.len || count > points.len - needed { ret (zero, TooLarge) }
        needed += count
        i += 1usize
    }
    var radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { radius = f64(bounds.height) * 0.5f64 }
    let inner = radius * f64(hole)
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    if !finite(f32(center_x)) || !finite(f32(center_y)) { ret (zero, Invalid) }
    var used = 0usize
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let fraction_of_total = f64(values[i]) / total
        let start = -1.5707963267948966f64 + 6.283185307179586f64 * cumulative / total
        cumulative += f64(values[i])
        let finish = start + 6.283185307179586f64 * fraction_of_total
        let steps = 2usize + usize(fraction_of_total * 96.0f64)
        let first = used
        var j = 0usize
        while j <= steps {
            let angle = start + (finish - start) * f64(j) / f64(steps)
            points[used] = Coord { x: f32(center_x + radius * math.cos[f64](angle)), y: f32(center_y + radius * math.sin[f64](angle)) }
            used += 1usize
            j += 1usize
        }
        j = 0usize
        while j <= steps {
            let angle = finish - (finish - start) * f64(j) / f64(steps)
            points[used] = Coord { x: f32(center_x + inner * math.cos[f64](angle)), y: f32(center_y + inner * math.sin[f64](angle)) }
            used += 1usize
            j += 1usize
        }
        layers[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

fn polar_point(center_x: f64, center_y: f64, radius: f64, angle: f64) -> Coord {
    ret Coord { x: f32(center_x + radius * math.cos[f64](angle)), y: f32(center_y + radius * math.sin[f64](angle)) }
}

// Normalize each radar axis against its own caller-supplied range. The same
// ranges and bounds can be reused for overlaying multiple series.
fn radar(values: []const f32, minimum: []const f32, maximum: []const f32, bounds: geometry.Rect, levels: usize, points: []Coord, guides: []Segment) -> (Layout, Layout, err) {
    if values.len < 3usize || minimum.len != values.len || maximum.len != values.len || levels == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, zero, Invalid) }
    if points.len <= values.len || guides.len / values.len <= levels { ret (zero, zero, TooLarge) }
    let count = values.len
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    var radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { radius = f64(bounds.height) * 0.5f64 }
    let turn = 6.283185307179586f64
    var i = 0usize
    while i < count {
        if !finite(values[i]) || !finite(minimum[i]) || !finite(maximum[i]) || maximum[i] <= minimum[i] || values[i] < minimum[i] || values[i] > maximum[i] { ret (zero, zero, Invalid) }
        let normalized = (f64(values[i]) - f64(minimum[i])) / (f64(maximum[i]) - f64(minimum[i]))
        let angle = -1.5707963267948966f64 + turn * f64(i) / f64(count)
        points[i] = polar_point(center_x, center_y, radius * normalized, angle)
        guides[i] = Segment { from: Coord { x: f32(center_x), y: f32(center_y) }, to: polar_point(center_x, center_y, radius, angle) }
        if !finite(points[i].x) || !finite(points[i].y) || !finite(guides[i].to.x) || !finite(guides[i].to.y) { ret (zero, zero, Invalid) }
        i += 1usize
    }
    points[count] = points[0usize]
    var used = count
    var level = 1usize
    while level <= levels {
        let ring_radius = radius * f64(level) / f64(levels)
        i = 0usize
        while i < count {
            let angle = -1.5707963267948966f64 + turn * f64(i) / f64(count)
            let next_angle = -1.5707963267948966f64 + turn * f64((i + 1usize) % count) / f64(count)
            guides[used] = Segment { from: polar_point(center_x, center_y, ring_radius, angle), to: polar_point(center_x, center_y, ring_radius, next_angle) }
            if !finite(guides[used].from.x) || !finite(guides[used].from.y) || !finite(guides[used].to.x) || !finite(guides[used].to.y) { ret (zero, zero, Invalid) }
            used += 1usize
            i += 1usize
        }
        level += 1usize
    }
    let polygon = Layout { kind: .Area, coords: points[..count + 1usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let guide_marks = Layout { kind: .Rug, coords: zero, segments: guides[..used], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret (polygon, guide_marks, ok)
}

// A, B and C are nonnegative parts of a composition; each row is closed to
// unit sum before projection. Corners are A (top), B (left), C (right).
fn ternary(a: []const f32, b: []const f32, c: []const f32, bounds: geometry.Rect, levels: usize, points: []Coord, guides: []Segment) -> (Layout, Layout, err) {
    if a.len == 0usize { ret (zero, zero, Empty) }
    if b.len != a.len || c.len != a.len || levels == 0usize || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if points.len < a.len || levels > guides.len / 3usize { ret (zero, zero, TooLarge) }
    let root3 = 1.7320508075688772f64
    var side = f64(bounds.width)
    if side > f64(bounds.height) * 2.0f64 / root3 { side = f64(bounds.height) * 2.0f64 / root3 }
    let height = side * root3 * 0.5f64
    let x = f64(bounds.x) + (f64(bounds.width) - side) * 0.5f64
    let y = f64(bounds.y) + (f64(bounds.height) - height) * 0.5f64
    let top = Coord { x: f32(x + side * 0.5f64), y: f32(y) }
    let left = Coord { x: f32(x), y: f32(y + height) }
    let right = Coord { x: f32(x + side), y: left.y }
    if !finite(top.x) || !finite(top.y) || !finite(left.x) || !finite(left.y) || !finite(right.x) { ret (zero, zero, Invalid) }
    var i = 0usize
    while i < a.len {
        if !finite(a[i]) || !finite(b[i]) || !finite(c[i]) || a[i] < 0.0 || b[i] < 0.0 || c[i] < 0.0 { ret (zero, zero, Invalid) }
        let total = f64(a[i]) + f64(b[i]) + f64(c[i])
        if total <= 0.0f64 { ret (zero, zero, Invalid) }
        let aa = f64(a[i]) / total
        let bb = f64(b[i]) / total
        let cc = f64(c[i]) / total
        points[i] = Coord { x: f32(aa * f64(top.x) + bb * f64(left.x) + cc * f64(right.x)), y: f32(aa * f64(top.y) + (bb + cc) * f64(left.y)) }
        if !finite(points[i].x) || !finite(points[i].y) { ret (zero, zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < levels {
        let t = f32(f64(i) / f64(levels))
        let u = 1.0 - t
        guides[i * 3usize] = Segment { from: Coord { x: left.x * u + top.x * t, y: left.y * u + top.y * t }, to: Coord { x: right.x * u + top.x * t, y: right.y * u + top.y * t } }
        guides[i * 3usize + 1usize] = Segment { from: Coord { x: top.x * u + right.x * t, y: top.y * u + right.y * t }, to: Coord { x: left.x * u + right.x * t, y: left.y * u + right.y * t } }
        guides[i * 3usize + 2usize] = Segment { from: Coord { x: top.x * u + left.x * t, y: top.y * u + left.y * t }, to: Coord { x: right.x * u + left.x * t, y: right.y * u + left.y * t } }
        i += 1usize
    }
    let marks = Layout { kind: .Scatter, coords: points[..a.len], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let grid = Layout { kind: .Rug, coords: zero, segments: guides[..levels * 3usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret (marks, grid, ok)
}

// X/Y locate tails in data space; U/V are vector components in data units.
// pixels_per_unit fixes their visual scale, independent of the axis domains.
fn quiver(x: []const f32, y: []const f32, u: []const f32, v: []const f32, bounds: geometry.Rect, pixels_per_unit: f32, head_size: f32, tails: []Coord, arrows: []Segment) -> (Layout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if y.len != x.len || u.len != x.len || v.len != x.len || !finite(pixels_per_unit) || pixels_per_unit <= 0.0 || !finite(head_size) || head_size <= 0.0 { ret (zero, Invalid) }
    if tails.len < x.len || x.len > arrows.len / 3usize { ret (zero, TooLarge) }
    let plot = spec(.Scatter, bounds, x, y)
    let (placed, place_error) = layout(&plot, tails, zero, zero)
    if place_error != ok { ret (zero, place_error) }
    var used = 0usize
    var i = 0usize
    while i < x.len {
        if !finite(u[i]) || !finite(v[i]) || !finite(placed.coords[i].x) || !finite(placed.coords[i].y) { ret (zero, Invalid) }
        let dx = f64(u[i]) * f64(pixels_per_unit)
        let dy = 0.0f64 - f64(v[i]) * f64(pixels_per_unit)
        let length = math.sqrt[f64](dx * dx + dy * dy)
        if length > 0.0f64 {
            let tail = placed.coords[i]
            let tip = Coord { x: f32(f64(tail.x) + dx), y: f32(f64(tail.y) + dy) }
            if !finite(tip.x) || !finite(tip.y) { ret (zero, Invalid) }
            var head = f64(head_size)
            if head > length * 0.4f64 { head = length * 0.4f64 }
            let ux = dx / length
            let uy = dy / length
            let left = Coord { x: f32(f64(tip.x) - head * ux - head * 0.5f64 * uy), y: f32(f64(tip.y) - head * uy + head * 0.5f64 * ux) }
            let right = Coord { x: f32(f64(tip.x) - head * ux + head * 0.5f64 * uy), y: f32(f64(tip.y) - head * uy - head * 0.5f64 * ux) }
            if !finite(left.x) || !finite(left.y) || !finite(right.x) || !finite(right.y) { ret (zero, Invalid) }
            arrows[used] = Segment { from: tail, to: tip }
            arrows[used + 1usize] = Segment { from: tip, to: left }
            arrows[used + 2usize] = Segment { from: tip, to: right }
            used += 3usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: arrows[..used], bars: zero, x_min: placed.x_min, x_max: placed.x_max, y_min: placed.y_min, y_max: placed.y_max }, ok)
}

// The regular grid is row-major with y increasing by row. Coordinates are
// clamped only to handle a midpoint on the outermost sample boundary.
fn flow_sample(u: []const f32, v: []const f32, columns: usize, rows: usize, x: f64, y: f64, xmin: f64, xmax: f64, ymin: f64, ymax: f64) -> (f64, f64) {
    var fx = (x - xmin) / (xmax - xmin) * f64(columns - 1usize)
    var fy = (y - ymin) / (ymax - ymin) * f64(rows - 1usize)
    if fx < 0.0f64 { fx = 0.0f64 }
    if fy < 0.0f64 { fy = 0.0f64 }
    if fx > f64(columns - 1usize) { fx = f64(columns - 1usize) }
    if fy > f64(rows - 1usize) { fy = f64(rows - 1usize) }
    var ix = usize(fx)
    var iy = usize(fy)
    if ix == columns - 1usize { ix -= 1usize }
    if iy == rows - 1usize { iy -= 1usize }
    let tx = fx - f64(ix)
    let ty = fy - f64(iy)
    let a = iy * columns + ix
    let b = a + columns
    let u0 = f64(u[a]) * (1.0f64 - tx) + f64(u[a + 1usize]) * tx
    let u1 = f64(u[b]) * (1.0f64 - tx) + f64(u[b + 1usize]) * tx
    let v0 = f64(v[a]) * (1.0f64 - tx) + f64(v[a + 1usize]) * tx
    let v1 = f64(v[b]) * (1.0f64 - tx) + f64(v[b + 1usize]) * tx
    ret (u0 * (1.0f64 - ty) + u1 * ty, v0 * (1.0f64 - ty) + v1 * ty)
}

// Fixed-distance midpoint integration follows direction, not field magnitude.
// ponytail: no streamline occupancy grid; add one if dense seeds visibly overlap.
fn streamlines(u: []const f32, v: []const f32, columns: usize, rows: usize, x_min: f32, x_max: f32, y_min: f32, y_max: f32, seeds: []const Coord, step: f32, max_steps: usize, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if seeds.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || rows < 2usize || rows > u.len / columns || u.len != rows * columns || v.len != u.len || !valid_bounds(bounds) || !finite(x_min) || !finite(x_max) || !finite(y_min) || !finite(y_max) || x_max <= x_min || y_max <= y_min || !finite(step) || step <= 0.0 || max_steps == 0usize { ret (zero, Invalid) }
    var i = 0usize
    while i < u.len {
        if !finite(u[i]) || !finite(v[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var used = 0usize
    i = 0usize
    while i < seeds.len {
        if !finite(seeds[i].x) || !finite(seeds[i].y) || seeds[i].x < x_min || seeds[i].x > x_max || seeds[i].y < y_min || seeds[i].y > y_max { ret (zero, Invalid) }
        var x = f64(seeds[i].x)
        var y = f64(seeds[i].y)
        var count = 0usize
        while count < max_steps {
            let (u0, v0) = flow_sample(u, v, columns, rows, x, y, f64(x_min), f64(x_max), f64(y_min), f64(y_max))
            let speed0 = math.sqrt[f64](u0 * u0 + v0 * v0)
            if speed0 == 0.0f64 { break }
            let middle_x = x + f64(step) * 0.5f64 * u0 / speed0
            let middle_y = y + f64(step) * 0.5f64 * v0 / speed0
            let (u1, v1) = flow_sample(u, v, columns, rows, middle_x, middle_y, f64(x_min), f64(x_max), f64(y_min), f64(y_max))
            let speed1 = math.sqrt[f64](u1 * u1 + v1 * v1)
            if speed1 == 0.0f64 { break }
            let dx = f64(step) * u1 / speed1
            let dy = f64(step) * v1 / speed1
            var stop = 1.0f64
            if dx > 0.0f64 && x + dx > f64(x_max) { stop = (f64(x_max) - x) / dx }
            if dx < 0.0f64 && x + dx < f64(x_min) { stop = (f64(x_min) - x) / dx }
            if dy > 0.0f64 && y + dy > f64(y_max) {
                let hit = (f64(y_max) - y) / dy
                if hit < stop { stop = hit }
            }
            if dy < 0.0f64 && y + dy < f64(y_min) {
                let hit = (f64(y_min) - y) / dy
                if hit < stop { stop = hit }
            }
            if stop <= 0.0f64 { break }
            let next_x = x + dx * stop
            let next_y = y + dy * stop
            if next_x == x && next_y == y { break }
            if used == segments.len { ret (zero, TooLarge) }
            let from = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (x - f64(x_min)) / (f64(x_max) - f64(x_min))), y: f32(f64(bounds.y) + f64(bounds.height) * (f64(y_max) - y) / (f64(y_max) - f64(y_min))) }
            let to = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (next_x - f64(x_min)) / (f64(x_max) - f64(x_min))), y: f32(f64(bounds.y) + f64(bounds.height) * (f64(y_max) - next_y) / (f64(y_max) - f64(y_min))) }
            if !finite(from.x) || !finite(from.y) || !finite(to.x) || !finite(to.y) { ret (zero, Invalid) }
            segments[used] = Segment { from: from, to: to }
            used += 1usize
            x = next_x
            y = next_y
            count += 1usize
            if stop < 1.0f64 { break }
        }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: segments[..used], bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }, ok)
}

// A two-dimensional delay embedding, (value[t], value[t+lag]), retains one
// shared numeric domain and a square panel so slopes remain comparable.
fn phase_space(values: []const f32, lag: usize, bounds: geometry.Rect, points: []Coord, segments: []Segment) -> (Layout, err) {
    if values.len < 3usize { ret (zero, Empty) }
    if lag == 0usize || lag >= values.len - 1usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    let count = values.len - lag
    if points.len < count || segments.len < count - 1usize { ret (zero, TooLarge) }
    let (raw_lo, raw_hi, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var lo = raw_lo
    var hi = raw_hi
    if lo == hi {
        lo -= 0.5
        hi += 0.5
    }
    if !finite(lo) || !finite(hi) || hi <= lo { ret (zero, Invalid) }
    var side = bounds.width
    if bounds.height < side { side = bounds.height }
    let square = geometry.rect(bounds.x + (bounds.width - side) * 0.5, bounds.y + (bounds.height - side) * 0.5, side, side)
    if !finite(square.x + side) || !finite(square.y + side) { ret (zero, Invalid) }
    let limits = [2]f32{ lo, hi }
    let plot = spec(.PointLine, square, values[..count], values[lag..])
    let (marks, layout_error) = layout_with_limits(&plot, points, segments, zero, limits[..], limits[..])
    ret (marks, layout_error)
}

// Threshold Euclidean distances between the same delay-embedded states.
// ponytail: the dense matrix is quadratic; use sparse tiles for long series.
fn recurrence(values: []const f32, lag: usize, radius: f32, bounds: geometry.Rect, cells: []Cell) -> (MatrixLayout, err) {
    if values.len < 3usize { ret (zero, Empty) }
    if lag == 0usize || lag >= values.len - 1usize || !valid_bounds(bounds) || !finite(radius) || radius < 0.0 { ret (zero, Invalid) }
    let count = values.len - lag
    if count > cells.len / count { ret (zero, TooLarge) }
    let (_, _, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    let width = f32(f64(bounds.width) / f64(count))
    let height = f32(f64(bounds.height) / f64(count))
    if width <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
    let threshold = f64(radius) * f64(radius)
    var row = 0usize
    while row < count {
        var column = 0usize
        while column < count {
            let dx = f64(values[row]) - f64(values[column])
            let dy = f64(values[row + lag]) - f64(values[column + lag])
            var present = 0.0f32
            if dx * dx + dy * dy <= threshold { present = 1.0 }
            let rect = geometry.rect(bounds.x + f32(column) * width, bounds.y + f32(row) * height, width, height)
            if !finite(rect.x) || !finite(rect.y) { ret (zero, Invalid) }
            cells[row * count + column] = Cell { rect: rect, value: present }
            column += 1usize
        }
        row += 1usize
    }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..count * count], columns: count, rows: count, value_min: 0.0, value_max: 1.0 }, ok)
}

// Drawdowns are fractional losses from the running peak; a new high returns to zero.
fn drawdown(x: []const f32, prices: []const f32, bounds: geometry.Rect, losses: []f32, points: []Coord) -> (Layout, err) {
    if prices.len < 2usize { ret (zero, Empty) }
    if x.len != prices.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if losses.len < prices.len || points.len / 2usize < prices.len { ret (zero, TooLarge) }
    var peak = prices[0usize]
    var i = 0usize
    while i < prices.len {
        if !finite(prices[i]) || prices[i] <= 0.0 { ret (zero, Invalid) }
        if prices[i] > peak { peak = prices[i] }
        losses[i] = f32(f64(prices[i]) / f64(peak) - 1.0f64)
        i += 1usize
    }
    let plot = spec(.Area, bounds, x, losses[..prices.len])
    var unused_segments: [1]Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, layout_error) = layout(&plot, points, unused_segments[..0usize], unused_bars[..0usize])
    ret (marks, layout_error)
}

// One padded numeric x domain aligns closing-price Line and nonnegative volume Bar.
fn price_volume(x: []const f32, prices: []const f32, volumes: []const f32, bounds: geometry.Rect, gap: f32, price_segments: []Segment, volume_bars: []geometry.Rect) -> (Layout, Layout, err) {
    if prices.len < 2usize { ret (zero, zero, Empty) }
    if x.len != prices.len || volumes.len != prices.len || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 || gap >= bounds.height { ret (zero, zero, Invalid) }
    if price_segments.len < prices.len - 1usize || volume_bars.len < prices.len { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < prices.len {
        if !finite(prices[i]) || prices[i] <= 0.0 || !finite(volumes[i]) || volumes[i] < 0.0 { ret (zero, zero, Invalid) }
        i += 1usize
    }
    let (xmin, xmax, _, _, step, domain_error) = ohlc_domain(x, prices, prices, prices, prices)
    if domain_error != ok { ret (zero, zero, domain_error) }
    let volume_height = (bounds.height - gap) * 0.34
    let price_height = bounds.height - gap - volume_height
    let price_bounds = geometry.rect(bounds.x, bounds.y, bounds.width, price_height)
    let volume_bounds = geometry.rect(bounds.x, bounds.y + price_height + gap, bounds.width, volume_height)
    if !valid_bounds(price_bounds) || !valid_bounds(volume_bounds) { ret (zero, zero, Invalid) }
    let width = bounds.width * step / (xmax - xmin) * 0.7
    if !finite(width) || width <= 0.0 { ret (zero, zero, Invalid) }
    let limits = [2]f32{ xmin, xmax }
    var unused_coords: [1]Coord = zero
    var unused_segments: [1]Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let price_plot = spec(.Line, price_bounds, x, prices)
    let (price_marks, price_error) = layout_with_limits(&price_plot, unused_coords[..0usize], price_segments, unused_bars[..0usize], limits[..], limits[..0usize])
    if price_error != ok { ret (zero, zero, price_error) }
    var volume_plot = spec(.Bar, volume_bounds, x, volumes)
    volume_plot.bar_width = width
    let (volume_marks, volume_error) = layout_with_limits(&volume_plot, unused_coords[..0usize], unused_segments[..0usize], volume_bars, limits[..], limits[..0usize])
    ret (price_marks, volume_marks, volume_error)
}

// Simple per-observation price returns and trailing sample SD, not annualized.
// ponytail: each window is recomputed with Welford (O(n*window)); slide the state only for long series.
fn returns_volatility(x: []const f32, prices: []const f32, window: usize, bounds: geometry.Rect, gap: f32, returns: []f32, volatility: []f32, return_segments: []Segment, volatility_segments: []Segment) -> (Layout, Layout, err) {
    if prices.len < 2usize { ret (zero, zero, Empty) }
    if x.len != prices.len || window < 2usize || window > prices.len - 2usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, zero, Invalid) }
    let return_count = prices.len - 1usize
    let volatility_count = prices.len - window
    if returns.len < return_count || volatility.len < volatility_count || return_segments.len < return_count - 1usize || volatility_segments.len < volatility_count - 1usize { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < prices.len {
        if !finite(prices[i]) || prices[i] <= 0.0 || !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, zero, Invalid) }
        if i > 0usize {
            returns[i - 1usize] = f32(f64(prices[i]) / f64(prices[i - 1usize]) - 1.0f64)
            if !finite(returns[i - 1usize]) { ret (zero, zero, Invalid) }
        }
        i += 1usize
    }
    var end = window - 1usize
    while end < return_count {
        var mean = 0.0f64
        var sum_squares = 0.0f64
        var j = 0usize
        while j < window {
            let value = f64(returns[end + 1usize - window + j])
            let delta = value - mean
            mean += delta / f64(j + 1usize)
            sum_squares += delta * (value - mean)
            j += 1usize
        }
        if sum_squares < 0.0f64 { sum_squares = 0.0f64 }
        volatility[end + 1usize - window] = f32(math.sqrt[f64](sum_squares / f64(window - 1usize)))
        if !finite(volatility[end + 1usize - window]) { ret (zero, zero, Invalid) }
        end += 1usize
    }
    var panels: [2]geometry.Rect = zero
    let (_, panel_error) = facet_grid(bounds, 1usize, 2usize, gap, panels[..])
    if panel_error != ok { ret (zero, zero, panel_error) }
    let (raw_min, raw_max, return_error) = extent(returns[..return_count])
    if return_error != ok { ret (zero, zero, return_error) }
    var low = raw_min
    var high = raw_max
    if low > 0.0 { low = 0.0 }
    if high < 0.0 { high = 0.0 }
    var return_limits = [2]f32{ low, high }
    if low == high {
        return_limits[0usize] = -0.5
        return_limits[1usize] = 0.5
    }
    let (_, vol_max, vol_error) = extent(volatility[..volatility_count])
    if vol_error != ok { ret (zero, zero, vol_error) }
    var vol_limits = [2]f32{ 0.0, vol_max }
    if vol_max == 0.0 { vol_limits[1usize] = 0.5 }
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let x_limits = [2]f32{ x[0usize], x[x.len - 1usize] }
    let return_plot = spec(.Line, panels[0usize], x[1usize..], returns[..return_count])
    let (return_marks, marks_error) = layout_with_limits(&return_plot, unused_coords[..0usize], return_segments, unused_bars[..0usize], x_limits[..], return_limits[..])
    if marks_error != ok { ret (zero, zero, marks_error) }
    let volatility_plot = spec(.Line, panels[1usize], x[window..], volatility[..volatility_count])
    let (volatility_marks, layout_error) = layout_with_limits(&volatility_plot, unused_coords[..0usize], volatility_segments, unused_bars[..0usize], x_limits[..], vol_limits[..])
    ret (return_marks, volatility_marks, layout_error)
}

// Two nonnegative traces share the same ordered time and value domains.
fn progress_lines(x: []const f32, actual: []const f32, reference: []const f32, bounds: geometry.Rect, actual_segments: []Segment, reference_segments: []Segment) -> (Layout, Layout, err) {
    if x.len < 2usize { ret (zero, zero, Empty) }
    if actual.len != x.len || reference.len != x.len || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if actual_segments.len < x.len - 1usize || reference_segments.len < x.len - 1usize { ret (zero, zero, TooLarge) }
    var maximum = 0.0f32
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) || !finite(actual[i]) || actual[i] < 0.0 || !finite(reference[i]) || reference[i] < 0.0 { ret (zero, zero, Invalid) }
        if actual[i] > maximum { maximum = actual[i] }
        if reference[i] > maximum { maximum = reference[i] }
        i += 1usize
    }
    if maximum == 0.0 { maximum = 1.0 }
    let x_limits = [2]f32{ x[0usize], x[x.len - 1usize] }
    let y_limits = [2]f32{ 0.0, maximum }
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let actual_spec = spec(.Line, bounds, x, actual)
    let (actual_marks, actual_error) = layout_with_limits(&actual_spec, unused_coords[..0usize], actual_segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    if actual_error != ok { ret (zero, zero, actual_error) }
    let reference_spec = spec(.Line, bounds, x, reference)
    let (reference_marks, reference_error) = layout_with_limits(&reference_spec, unused_coords[..0usize], reference_segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    ret (actual_marks, reference_marks, reference_error)
}

// Ideal remaining work falls linearly from the first observation to zero at
// the last observed time; actual increases are allowed when scope changes.
fn burndown(x: []const f32, remaining: []const f32, bounds: geometry.Rect, ideal: []f32, remaining_segments: []Segment, ideal_segments: []Segment) -> (Layout, Layout, err) {
    if x.len < 2usize { ret (zero, zero, Empty) }
    if remaining.len != x.len || !finite(x[0usize]) || !finite(x[x.len - 1usize]) || x[x.len - 1usize] <= x[0usize] || !finite(remaining[0usize]) || remaining[0usize] < 0.0 { ret (zero, zero, Invalid) }
    if ideal.len < x.len { ret (zero, zero, TooLarge) }
    let span = f64(x[x.len - 1usize]) - f64(x[0usize])
    var i = 0usize
    while i < x.len {
        ideal[i] = f32(f64(remaining[0usize]) * (1.0f64 - (f64(x[i]) - f64(x[0usize])) / span))
        if !finite(ideal[i]) { ret (zero, zero, Invalid) }
        i += 1usize
    }
    let (actual_marks, ideal_marks, pair_error) = progress_lines(x, remaining, ideal[..x.len], bounds, remaining_segments, ideal_segments)
    ret (actual_marks, ideal_marks, pair_error)
}

// Scope may change, but completed work cannot exceed it at any observation.
fn burnup(x: []const f32, completed: []const f32, scope: []const f32, bounds: geometry.Rect, completed_segments: []Segment, scope_segments: []Segment) -> (Layout, Layout, err) {
    if completed.len != scope.len { ret (zero, zero, Invalid) }
    var i = 0usize
    while i < completed.len {
        if completed[i] > scope[i] { ret (zero, zero, Invalid) }
        i += 1usize
    }
    let (completed_marks, scope_marks, pair_error) = progress_lines(x, completed, scope, bounds, completed_segments, scope_segments)
    ret (completed_marks, scope_marks, pair_error)
}

// Planned value may continue beyond the measured earned-value/actual-cost
// prefix. All three curves use the full planned x and y domains.
fn earned_value(x: []const f32, planned: []const f32, earned: []const f32, actual: []const f32, bounds: geometry.Rect, planned_segments: []Segment, earned_segments: []Segment, actual_segments: []Segment) -> (Layout, Layout, Layout, err) {
    if x.len < 2usize { ret (zero, zero, zero, Empty) }
    if planned.len != x.len || earned.len != actual.len || earned.len < 2usize || earned.len > x.len || !valid_bounds(bounds) { ret (zero, zero, zero, Invalid) }
    if planned_segments.len < x.len - 1usize || earned_segments.len < earned.len - 1usize || actual_segments.len < actual.len - 1usize { ret (zero, zero, zero, TooLarge) }
    var maximum = 0.0f32
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) || !finite(planned[i]) || planned[i] < 0.0 { ret (zero, zero, zero, Invalid) }
        if planned[i] > maximum { maximum = planned[i] }
        if i < earned.len {
            if !finite(earned[i]) || earned[i] < 0.0 || !finite(actual[i]) || actual[i] < 0.0 { ret (zero, zero, zero, Invalid) }
            if earned[i] > maximum { maximum = earned[i] }
            if actual[i] > maximum { maximum = actual[i] }
        }
        i += 1usize
    }
    if maximum == 0.0 { maximum = 1.0 }
    let x_limits = [2]f32{ x[0usize], x[x.len - 1usize] }
    let y_limits = [2]f32{ 0.0, maximum }
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let planned_spec = spec(.Line, bounds, x, planned)
    let (planned_marks, planned_error) = layout_with_limits(&planned_spec, unused_coords[..0usize], planned_segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    if planned_error != ok { ret (zero, zero, zero, planned_error) }
    let earned_spec = spec(.Line, bounds, x[..earned.len], earned)
    let (earned_marks, earned_error) = layout_with_limits(&earned_spec, unused_coords[..0usize], earned_segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    if earned_error != ok { ret (zero, zero, zero, earned_error) }
    let actual_spec = spec(.Line, bounds, x[..actual.len], actual)
    let (actual_marks, actual_error) = layout_with_limits(&actual_spec, unused_coords[..0usize], actual_segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    ret (planned_marks, earned_marks, actual_marks, actual_error)
}

// Equal-angle rose sectors. Square-root radii make sector area proportional
// to each nonnegative pre-binned weight, as in a circular histogram.
fn rose(values: []const f32, bounds: geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if layers.len < values.len { ret (zero, TooLarge) }
    let steps = 2usize + 96usize / values.len
    let per_sector = steps + 2usize
    if values.len > points.len / per_sector { ret (zero, TooLarge) }
    var largest = 0.0f32
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        if values[i] > largest { largest = values[i] }
        i += 1usize
    }
    if largest <= 0.0 { ret (zero, Invalid) }
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    var outer = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { outer = f64(bounds.height) * 0.5f64 }
    let turn = 6.283185307179586f64
    var used = 0usize
    i = 0usize
    while i < values.len {
        let start = -1.5707963267948966f64 + turn * (f64(i) - 0.5f64) / f64(values.len)
        let finish = start + turn / f64(values.len)
        let radius = outer * math.sqrt[f64](f64(values[i]) / f64(largest))
        let first = used
        points[used] = Coord { x: f32(center_x), y: f32(center_y) }
        used += 1usize
        var j = 0usize
        while j <= steps {
            let angle = start + (finish - start) * f64(j) / f64(steps)
            points[used] = polar_point(center_x, center_y, radius, angle)
            if !finite(points[used].x) || !finite(points[used].y) { ret (zero, Invalid) }
            used += 1usize
            j += 1usize
        }
        layers[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: f32(values.len), y_min: 0.0, y_max: largest }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

// Half-ring gauge: background, measured value and target rule, in paint order.
// The ring fits a semicircle inside bounds; the caller owns all three marks.
fn gauge(value: f32, target_value: f32, maximum: f32, bounds: geometry.Rect, hole: f32, points: []Coord, target_line: []Segment, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(value) || !finite(target_value) || !finite(maximum) || maximum <= 0.0 || value < 0.0 || value > maximum || target_value < 0.0 || target_value > maximum || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    if points.len < 196usize || target_line.len == 0usize || layers.len < 3usize { ret (zero, TooLarge) }
    var radius = f64(bounds.width) * 0.5f64
    if f64(bounds.height) < radius { radius = f64(bounds.height) }
    if radius <= 0.0f64 { ret (zero, Invalid) }
    let inner = radius * f64(hole)
    let cx = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let cy = f64(bounds.y) + f64(bounds.height)
    let pi = 3.141592653589793f64
    let fractions = [2]f64{ 1.0f64, f64(value) / f64(maximum) }
    var layer = 0usize
    while layer < 2usize {
        let first = layer * 98usize
        var j = 0usize
        while j <= 48usize {
            let angle = pi + pi * fractions[layer] * f64(j) / 48.0f64
            points[first + j] = Coord { x: f32(cx + radius * math.cos[f64](angle)), y: f32(cy + radius * math.sin[f64](angle)) }
            let reverse = pi + pi * fractions[layer] * f64(48usize - j) / 48.0f64
            points[first + 49usize + j] = Coord { x: f32(cx + inner * math.cos[f64](reverse)), y: f32(cy + inner * math.sin[f64](reverse)) }
            if !finite(points[first + j].x) || !finite(points[first + j].y) || !finite(points[first + 49usize + j].x) || !finite(points[first + 49usize + j].y) { ret (zero, Invalid) }
            j += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: points[first..first + 98usize], segments: zero, bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
        layer += 1usize
    }
    let angle = pi + pi * f64(target_value) / f64(maximum)
    let start = Coord { x: f32(cx + inner * 0.85f64 * math.cos[f64](angle)), y: f32(cy + inner * 0.85f64 * math.sin[f64](angle)) }
    let end = Coord { x: f32(cx + radius * math.cos[f64](angle)), y: f32(cy + radius * math.sin[f64](angle)) }
    if !finite(start.x) || !finite(start.y) || !finite(end.x) || !finite(end.y) { ret (zero, Invalid) }
    target_line[0usize] = Segment { from: start, to: end }
    layers[2usize] = Layout { kind: .Rug, coords: zero, segments: target_line[..1usize], bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    ret (layers[..3usize], ok)
}

// Text metrics are font-size-normalized widths and heights measured by the
// caller. Larger weights get larger type; exact excluded tokens are omitted.
// ponytail: deterministic spiral placement scans prior boxes; use a spatial index
// and a better packing search when clouds of hundreds of tokens are needed.
fn word_cloud(words: []const str, weights: []const f32, unit_widths: []const f32, unit_heights: []const f32, baseline_unit: f32, excluded: []const str, bounds: geometry.Rect, min_size: f32, max_size: f32, gap: f32, order: []usize, marks: []CloudWord) -> ([]CloudWord, err) {
    if words.len == 0usize { ret (zero, Empty) }
    if weights.len != words.len || unit_widths.len != words.len || unit_heights.len != words.len || !valid_bounds(bounds) || !finite(baseline_unit) || baseline_unit <= 0.0 || !finite(min_size) || !finite(max_size) || min_size <= 0.0 || max_size < min_size || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if order.len < words.len || marks.len < words.len { ret (zero, TooLarge) }
    var active = 0usize
    var maximum = 0.0f32
    var i = 0usize
    while i < words.len {
        if words[i].len == 0usize || !text_layout.valid_utf8(words[i]) || !finite(weights[i]) || weights[i] < 0.0 || !finite(unit_widths[i]) || unit_widths[i] <= 0.0 || !finite(unit_heights[i]) || unit_heights[i] <= 0.0 { ret (zero, Invalid) }
        var prior = 0usize
        while prior < i {
            if str.eq(words[prior], words[i]) { ret (zero, Invalid) }
            prior += 1usize
        }
        var skip = weights[i] == 0.0
        var j = 0usize
        while j < excluded.len {
            if str.eq(words[i], excluded[j]) { skip = true }
            j += 1usize
        }
        if !skip {
            order[active] = i
            active += 1usize
            if weights[i] > maximum { maximum = weights[i] }
        }
        i += 1usize
    }
    if active == 0usize { ret (zero, Empty) }
    i = 1usize
    while i < active {
        let selected = order[i]
        var j = i
        while j > 0usize && weights[order[j - 1usize]] < weights[selected] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = selected
        i += 1usize
    }
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    var used = 0usize
    while used < active {
        let index = order[used]
        var size = max_size * f32(math.sqrt[f64](f64(weights[index]) / f64(maximum)))
        if size < min_size { size = min_size }
        let width = unit_widths[index] * size
        let height = unit_heights[index] * size
        if !finite(size) || !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 || width > bounds.width || height > bounds.height { ret (zero, TooLarge) }
        var placed = false
        var attempt = 0usize
        while attempt < 4096usize && !placed {
            let angle = f64(attempt) * 2.399963229728653f64
            let radius = 3.0f64 * math.sqrt[f64](f64(attempt))
            let x = f32(center_x + radius * math.cos[f64](angle) - f64(width) * 0.5f64)
            let y = f32(center_y + radius * math.sin[f64](angle) - f64(height) * 0.5f64)
            if finite(x) && finite(y) && x >= bounds.x && y >= bounds.y && x + width <= bounds.x + bounds.width && y + height <= bounds.y + bounds.height {
                var free = true
                var prior = 0usize
                while prior < used {
                    let box = marks[prior].box
                    if x < box.x + box.width + gap && x + width + gap > box.x && y < box.y + box.height + gap && y + height + gap > box.y { free = false }
                    prior += 1usize
                }
                if free {
                    let box = geometry.rect(x, y, width, height)
                    let anchor = Coord { x: x, y: y + baseline_unit * size }
                    if !finite(anchor.y) { ret (zero, Invalid) }
                    marks[used] = CloudWord { label: Label { text: words[index], anchor: anchor, align: .Left }, size: size, box: box }
                    placed = true
                }
            }
            attempt += 1usize
        }
        if !placed { ret (zero, TooLarge) }
        used += 1usize
    }
    ret (marks[..active], ok)
}

// Floating low-to-high bars use an explicit shared numeric domain and
// categorical rows. Unlike a dumbbell, the interval itself carries area;
// endpoint caps remain a separate stroke layer for independent styling.
fn range_intervals(items: []const RangeInterval, rows: usize, domain_min: f64, domain_max: f64, bounds: geometry.Rect, thickness: f32, bands: []geometry.Rect, endpoints: []Segment) -> (RangeIntervalLayout, err) {
    if items.len == 0usize { ret (zero, Empty) }
    if rows == 0usize || !finite64(domain_min) || !finite64(domain_max) || domain_max <= domain_min || !finite64(domain_max - domain_min) || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(thickness) || thickness <= 0.0 || thickness > 1.0 { ret (zero, Invalid) }
    let x_min = f32(domain_min)
    let x_max = f32(domain_max)
    let y_max = f32(rows)
    if !finite(x_min) || !finite(x_max) || x_max <= x_min || !finite(y_max) { ret (zero, Invalid) }
    if bands.len < items.len || endpoints.len / 2usize < items.len { ret (zero, TooLarge) }
    let lane_height = bounds.height / f32(rows)
    let bar_height = lane_height * thickness
    let cap_height = lane_height * 0.8
    if !finite(lane_height) || !finite(bar_height) || lane_height < 10.0 || bar_height < 2.0 { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let item = items[i]
        if item.row >= rows || !finite64(item.lower) || !finite64(item.upper) || item.lower < domain_min || item.upper > domain_max || item.upper <= item.lower { ret (zero, Invalid) }
        let left = bounds.x + bounds.width * f32((item.lower - domain_min) / (domain_max - domain_min))
        let right = bounds.x + bounds.width * f32((item.upper - domain_min) / (domain_max - domain_min))
        let middle = bounds.y + (f32(item.row) + 0.5) * lane_height
        if !finite(left) || !finite(right) || !finite(middle) || right <= left { ret (zero, Invalid) }
        bands[i] = geometry.rect(left, middle - bar_height * 0.5, right - left, bar_height)
        endpoints[2usize * i] = Segment { from: Coord { x: left, y: middle - cap_height * 0.5 }, to: Coord { x: left, y: middle + cap_height * 0.5 } }
        endpoints[2usize * i + 1usize] = Segment { from: Coord { x: right, y: middle - cap_height * 0.5 }, to: Coord { x: right, y: middle + cap_height * 0.5 } }
        i += 1usize
    }
    let ranges = Layout { kind: .Bar, coords: zero, segments: zero, bars: bands[..items.len], x_min: x_min, x_max: x_max, y_min: 0.0, y_max: y_max }
    let caps = Layout { kind: .Rug, coords: zero, segments: endpoints[..2usize * items.len], bars: zero, x_min: x_min, x_max: x_max, y_min: 0.0, y_max: y_max }
    ret (RangeIntervalLayout { ranges: ranges, caps: caps }, ok)
}

// A football field compares one valuation interval per method on a single
// caller-specified value basis. The caller owns labels, colours and units;
// this composes the generic capped intervals with a shared benchmark rule.
fn football_field(methods: []const RangeInterval, domain_min: f64, domain_max: f64, benchmark_value: f64, bounds: geometry.Rect, bands: []geometry.Rect, endpoints: []Segment, benchmark_line: []Segment) -> (FootballFieldLayout, err) {
    if methods.len == 0usize { ret (zero, Empty) }
    if !finite64(benchmark_value) || benchmark_value < domain_min || benchmark_value > domain_max { ret (zero, Invalid) }
    if benchmark_line.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < methods.len {
        if methods[i].row != i { ret (zero, Invalid) }
        i += 1usize
    }
    let (intervals, interval_error) = range_intervals(methods, methods.len, domain_min, domain_max, bounds, 0.55f32, bands, endpoints)
    if interval_error != ok { ret (zero, interval_error) }
    let x = bounds.x + bounds.width * f32((benchmark_value - domain_min) / (domain_max - domain_min))
    if !finite(x) { ret (zero, Invalid) }
    benchmark_line[0usize] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
    let benchmark = Layout { kind: .Rug, coords: zero, segments: benchmark_line[..1usize], bars: zero, x_min: intervals.ranges.x_min, x_max: intervals.ranges.x_max, y_min: 0.0f32, y_max: f32(methods.len) }
    ret (FootballFieldLayout { ranges: intervals.ranges, caps: intervals.caps, benchmark: benchmark }, ok)
}

// Task durations and completion fractions share a numeric time domain and
// categorical rows. Both layers reuse ordinary Bar scene/SVG adapters.
fn gantt(tasks: []const GanttTask, rows: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, row_gap: f32, spans: []geometry.Rect, completed: []geometry.Rect) -> (Layout, Layout, err) {
    if tasks.len == 0usize { ret (zero, zero, Empty) }
    if rows == 0usize || !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !valid_bounds(bounds) || !finite(row_gap) || row_gap < 0.0 { ret (zero, zero, Invalid) }
    let x_min = f32(domain_start)
    let x_max = f32(domain_end)
    let y_max = f32(rows)
    if !finite(x_min) || !finite(x_max) || x_max <= x_min || !finite(y_max) { ret (zero, zero, Invalid) }
    if spans.len < tasks.len || completed.len < tasks.len { ret (zero, zero, TooLarge) }
    let total_gap = row_gap * f32(rows - 1usize)
    if !finite(total_gap) || total_gap >= bounds.height { ret (zero, zero, Invalid) }
    let lane_height = (bounds.height - total_gap) / f32(rows)
    let bar_height = lane_height * 0.64
    if !finite(lane_height) || !finite(bar_height) || bar_height <= 0.0 { ret (zero, zero, Invalid) }
    var i = 0usize
    while i < tasks.len {
        let task = tasks[i]
        if task.row >= rows || !finite64(task.start) || !finite64(task.end) || task.start < domain_start || task.end > domain_end || task.end <= task.start || !finite(task.complete) || task.complete < 0.0 || task.complete > 1.0 { ret (zero, zero, Invalid) }
        let left = bounds.x + bounds.width * f32((task.start - domain_start) / (domain_end - domain_start))
        let right = bounds.x + bounds.width * f32((task.end - domain_start) / (domain_end - domain_start))
        let top = bounds.y + f32(task.row) * (lane_height + row_gap) + (lane_height - bar_height) * 0.5
        if !finite(left) || !finite(right) || !finite(top) || right <= left { ret (zero, zero, Invalid) }
        spans[i] = geometry.rect(left, top, right - left, bar_height)
        completed[i] = geometry.rect(left, top, (right - left) * task.complete, bar_height)
        i += 1usize
    }
    let whole = Layout { kind: .Bar, coords: zero, segments: zero, bars: spans[..tasks.len], x_min: x_min, x_max: x_max, y_min: 0.0, y_max: y_max }
    let done = Layout { kind: .Bar, coords: zero, segments: zero, bars: completed[..tasks.len], x_min: x_min, x_max: x_max, y_min: 0.0, y_max: y_max }
    ret (whole, done, ok)
}

// Exact assignment boundaries form variable-width bars. The split between
// normal and excess height is capacity, not an averaged time-bin estimate.
fn resource_histogram(spans: []const ResourceSpan, domain_start: f64, domain_end: f64, capacity: f64, bounds: geometry.Rect, edges: []f64, loads: []f64, normal_bars: []geometry.Rect, excess_bars: []geometry.Rect, capacity_rule: []Segment) -> (Layout, Layout, Layout, err) {
    if spans.len == 0usize { ret (zero, zero, zero, Empty) }
    if !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !finite64(domain_end - domain_start) || !finite64(capacity) || capacity <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, zero, zero, Invalid) }
    if !finite(f32(domain_start)) || !finite(f32(domain_end)) || f32(domain_end) <= f32(domain_start) || !finite(f32(capacity)) || f32(capacity) <= 0.0 { ret (zero, zero, zero, Invalid) }
    if edges.len < 2usize || spans.len > (edges.len - 2usize) / 2usize || capacity_rule.len == 0usize { ret (zero, zero, zero, TooLarge) }
    var i = 0usize
    while i < spans.len {
        let span = spans[i]
        if !finite64(span.start) || !finite64(span.end) || span.start < domain_start || span.end > domain_end || span.end <= span.start || !finite64(span.units) || span.units < 0.0f64 { ret (zero, zero, zero, Invalid) }
        i += 1usize
    }
    edges[0usize] = domain_start
    edges[1usize] = domain_end
    i = 0usize
    while i < spans.len {
        edges[2usize + i * 2usize] = spans[i].start
        edges[3usize + i * 2usize] = spans[i].end
        i += 1usize
    }
    let count = 2usize + spans.len * 2usize
    i = 1usize
    while i < count {
        let value = edges[i]
        var j = i
        while j > 0usize && edges[j - 1usize] > value {
            edges[j] = edges[j - 1usize]
            j -= 1usize
        }
        edges[j] = value
        i += 1usize
    }
    var distinct = 0usize
    i = 0usize
    while i < count {
        if distinct == 0usize || edges[i] > edges[distinct - 1usize] {
            edges[distinct] = edges[i]
            distinct += 1usize
        }
        i += 1usize
    }
    let periods = distinct - 1usize
    if loads.len < periods || normal_bars.len < periods || excess_bars.len < periods { ret (zero, zero, zero, TooLarge) }
    var maximum = capacity
    i = 0usize
    while i < periods {
        let middle = edges[i] + (edges[i + 1usize] - edges[i]) * 0.5f64
        var demand = 0.0f64
        var j = 0usize
        while j < spans.len {
            if spans[j].start <= middle && middle < spans[j].end { demand += spans[j].units }
            if !finite64(demand) || !finite(f32(demand)) { ret (zero, zero, zero, Invalid) }
            j += 1usize
        }
        loads[i] = demand
        if demand > maximum { maximum = demand }
        i += 1usize
    }
    let bottom = bounds.y + bounds.height
    let capacity_y = bottom - bounds.height * f32(capacity / maximum)
    if !finite(capacity_y) { ret (zero, zero, zero, Invalid) }
    i = 0usize
    while i < periods {
        let left = bounds.x + bounds.width * f32((edges[i] - domain_start) / (domain_end - domain_start))
        let right = bounds.x + bounds.width * f32((edges[i + 1usize] - domain_start) / (domain_end - domain_start))
        let total_height = bounds.height * f32(loads[i] / maximum)
        var normal_height = total_height
        if loads[i] > capacity { normal_height = bounds.height * f32(capacity / maximum) }
        if !finite(left) || !finite(right) || right <= left || !finite(total_height) || !finite(normal_height) { ret (zero, zero, zero, Invalid) }
        normal_bars[i] = geometry.rect(left, bottom - normal_height, right - left, normal_height)
        excess_bars[i] = geometry.rect(left, bottom - total_height, right - left, total_height - normal_height)
        i += 1usize
    }
    capacity_rule[0usize] = Segment { from: Coord { x: bounds.x, y: capacity_y }, to: Coord { x: bounds.x + bounds.width, y: capacity_y } }
    let normal = Layout { kind: .Bar, coords: zero, segments: zero, bars: normal_bars[..periods], x_min: f32(domain_start), x_max: f32(domain_end), y_min: 0.0, y_max: f32(maximum) }
    let excess = Layout { kind: .Bar, coords: zero, segments: zero, bars: excess_bars[..periods], x_min: f32(domain_start), x_max: f32(domain_end), y_min: 0.0, y_max: f32(maximum) }
    let limit = Layout { kind: .Rug, coords: zero, segments: capacity_rule[..1usize], bars: zero, x_min: f32(domain_start), x_max: f32(domain_end), y_min: 0.0, y_max: f32(maximum) }
    ret (normal, excess, limit, ok)
}

// Lanes partition roles; stages order steps. Five strokes per link include
// an orthogonal elbow and an arrowhead. Labels and lane colours stay caller-side.
fn swimlane(steps: []const SwimlaneStep, links: []const SwimlaneLink, lane_count: usize, stage_count: usize, bounds: geometry.Rect, lane_bands: []geometry.Rect, boxes: []geometry.Rect, arrows: []Segment) -> (Layout, Layout, err) {
    if steps.len == 0usize { ret (zero, zero, Empty) }
    if lane_count == 0usize || stage_count == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, zero, Invalid) }
    if lane_bands.len < lane_count || boxes.len < steps.len || arrows.len / 5usize < links.len { ret (zero, zero, TooLarge) }
    let lane_height = bounds.height / f32(lane_count)
    let stage_width = bounds.width / f32(stage_count)
    let box_width = stage_width * 0.72
    let box_height = lane_height * 0.44
    if !finite(lane_height) || !finite(stage_width) || !finite(box_width) || !finite(box_height) || box_width <= 0.0 || box_height <= 0.0 { ret (zero, zero, Invalid) }
    var i = 0usize
    while i < steps.len {
        if steps[i].lane >= lane_count || steps[i].stage >= stage_count { ret (zero, zero, Invalid) }
        var j = 0usize
        while j < i {
            if steps[j].lane == steps[i].lane && steps[j].stage == steps[i].stage { ret (zero, zero, Invalid) }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < links.len {
        let link = links[i]
        if link.from >= steps.len || link.to >= steps.len || steps[link.from].stage >= steps[link.to].stage { ret (zero, zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < lane_count {
        lane_bands[i] = geometry.rect(bounds.x, bounds.y + lane_height * f32(i), bounds.width, lane_height)
        i += 1usize
    }
    i = 0usize
    while i < steps.len {
        let step = steps[i]
        let x = bounds.x + stage_width * f32(step.stage) + (stage_width - box_width) * 0.5
        let y = bounds.y + lane_height * f32(step.lane) + (lane_height - box_height) * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        i += 1usize
    }
    i = 0usize
    while i < links.len {
        let from = boxes[links[i].from]
        let to = boxes[links[i].to]
        let x0 = from.x + from.width
        let x1 = to.x
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let middle = x0 + (x1 - x0) * 0.5
        let head = (x1 - x0) * 0.18
        if !finite(x0) || !finite(x1) || !finite(y0) || !finite(y1) || !finite(middle) || !finite(head) || head <= 0.0 { ret (zero, zero, Invalid) }
        let first = i * 5usize
        let tip = Coord { x: x1, y: y1 }
        arrows[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: middle, y: y0 } }
        arrows[first + 1usize] = Segment { from: Coord { x: middle, y: y0 }, to: Coord { x: middle, y: y1 } }
        arrows[first + 2usize] = Segment { from: Coord { x: middle, y: y1 }, to: tip }
        arrows[first + 3usize] = Segment { from: Coord { x: x1 - head, y: y1 - head * 0.7 }, to: tip }
        arrows[first + 4usize] = Segment { from: Coord { x: x1 - head, y: y1 + head * 0.7 }, to: tip }
        i += 1usize
    }
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..steps.len], x_min: 0.0, x_max: f32(stage_count), y_min: 0.0, y_max: f32(lane_count) }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..links.len * 5usize], bars: zero, x_min: 0.0, x_max: f32(stage_count), y_min: 0.0, y_max: f32(lane_count) }
    ret (nodes, connectors, ok)
}

// A board's columns are policy names; card order within each column follows
// input order. Zero limit means unrestricted, while a breach stays visible.
fn kanban(cards: []const KanbanCard, limits: []const usize, bounds: geometry.Rect, gutter: f32, padding: f32, header_height: f32, card_gap: f32, columns: []geometry.Rect, card_boxes: []geometry.Rect, status: []KanbanStatus, next_y: []f32) -> (Layout, Layout, err) {
    if limits.len == 0usize { ret (zero, zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(gutter) || gutter < 0.0 || !finite(padding) || padding < 0.0 || !finite(header_height) || header_height <= 0.0 || !finite(card_gap) || card_gap < 0.0 { ret (zero, zero, Invalid) }
    if columns.len < limits.len || card_boxes.len < cards.len || status.len < limits.len || next_y.len < limits.len { ret (zero, zero, TooLarge) }
    let total_gap = gutter * f32(limits.len - 1usize)
    let column_width = (bounds.width - total_gap) / f32(limits.len)
    let card_width = column_width - padding * 2.0
    if !finite(total_gap) || !finite(column_width) || !finite(card_width) || column_width <= 0.0 || card_width <= 0.0 || header_height + padding * 2.0 >= bounds.height { ret (zero, zero, Invalid) }
    var i = 0usize
    while i < cards.len {
        if cards[i].column >= limits.len || !finite(cards[i].height) || cards[i].height <= 0.0 { ret (zero, zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < limits.len {
        let x = bounds.x + f32(i) * (column_width + gutter)
        if !finite(x) || !finite(x + column_width) { ret (zero, zero, Invalid) }
        columns[i] = geometry.rect(x, bounds.y, column_width, bounds.height)
        next_y[i] = bounds.y + header_height + padding
        status[i] = KanbanStatus { count: 0usize, limit: limits[i], exceeded: false }
        i += 1usize
    }
    i = 0usize
    while i < cards.len {
        let card = cards[i]
        let column = card.column
        let y = next_y[column]
        let bottom = y + card.height
        if !finite(bottom) || bottom > bounds.y + bounds.height - padding { ret (zero, zero, TooLarge) }
        card_boxes[i] = geometry.rect(columns[column].x + padding, y, card_width, card.height)
        next_y[column] = bottom + card_gap
        status[column].count += 1usize
        i += 1usize
    }
    i = 0usize
    while i < limits.len {
        status[i].exceeded = status[i].limit > 0usize && status[i].count > status[i].limit
        i += 1usize
    }
    let background = Layout { kind: .Bar, coords: zero, segments: zero, bars: columns[..limits.len], x_min: 0.0, x_max: f32(limits.len), y_min: 0.0, y_max: 1.0 }
    let items = Layout { kind: .Bar, coords: zero, segments: zero, bars: card_boxes[..cards.len], x_min: 0.0, x_max: f32(limits.len), y_min: 0.0, y_max: 1.0 }
    ret (background, items, ok)
}

// Activity-on-node PERT uses the three-point mean and variance. CPM timing is
// unconstrained elapsed time: no calendars, leads/lags or resource levelling.
// The caller supplies all work arrays; a cycle or invalid estimate is refused.
fn pert_cpm_schedule(activities: []const CpmActivity, dependencies: []const CpmDependency, timings: []CpmTiming, work: CpmWork) -> (CpmSummary, err) {
    let n = activities.len
    if n == 0usize { ret (zero, Empty) }
    if timings.len < n || work.indegree.len < n || work.head.len < n || work.order.len < n || work.next.len < dependencies.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        let task = activities[i]
        if !finite64(task.optimistic) || !finite64(task.likely) || !finite64(task.pessimistic) || task.optimistic < 0.0f64 || task.optimistic > task.likely || task.likely > task.pessimistic { ret (zero, Invalid) }
        let expected = (task.optimistic + 4.0f64 * task.likely + task.pessimistic) / 6.0f64
        let spread = (task.pessimistic - task.optimistic) / 6.0f64
        let variance = spread * spread
        if !finite64(expected) || !finite64(variance) { ret (zero, Invalid) }
        timings[i] = CpmTiming { expected: expected, variance: variance, earliest_start: 0.0f64, earliest_finish: 0.0f64, latest_start: 0.0f64, latest_finish: 0.0f64, slack: 0.0f64, stage: 0usize, critical: false }
        work.indegree[i] = 0usize
        work.head[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < dependencies.len {
        let link = dependencies[i]
        if link.from >= n || link.to >= n || link.from == link.to { ret (zero, Invalid) }
        work.indegree[link.to] += 1usize
        work.next[i] = work.head[link.from]
        work.head[link.from] = i + 1usize
        i += 1usize
    }
    var tail = 0usize
    i = 0usize
    while i < n {
        if work.indegree[i] == 0usize {
            work.order[tail] = i
            tail += 1usize
        }
        i += 1usize
    }
    var front = 0usize
    var duration = 0.0f64
    var stages = 0usize
    while front < tail {
        let node = work.order[front]
        let finish = timings[node].earliest_start + timings[node].expected
        if !finite64(finish) { ret (zero, Invalid) }
        timings[node].earliest_finish = finish
        if finish > duration { duration = finish }
        if timings[node].stage + 1usize > stages { stages = timings[node].stage + 1usize }
        var edge = work.head[node]
        while edge != 0usize {
            let child = dependencies[edge - 1usize].to
            if finish > timings[child].earliest_start { timings[child].earliest_start = finish }
            if timings[node].stage + 1usize > timings[child].stage { timings[child].stage = timings[node].stage + 1usize }
            work.indegree[child] -= 1usize
            if work.indegree[child] == 0usize {
                work.order[tail] = child
                tail += 1usize
            }
            edge = work.next[edge - 1usize]
        }
        front += 1usize
    }
    if tail != n { ret (zero, Invalid) }
    let tolerance = (duration + 1.0f64) * 0.00000001f64
    var critical_count = 0usize
    i = n
    while i > 0usize {
        i -= 1usize
        let node = work.order[i]
        var latest_finish = duration
        var edge = work.head[node]
        while edge != 0usize {
            let child = dependencies[edge - 1usize].to
            if timings[child].latest_start < latest_finish { latest_finish = timings[child].latest_start }
            edge = work.next[edge - 1usize]
        }
        let latest_start = latest_finish - timings[node].expected
        let slack = latest_start - timings[node].earliest_start
        if !finite64(latest_start) || !finite64(slack) || slack < 0.0f64 - tolerance { ret (zero, Invalid) }
        timings[node].latest_finish = latest_finish
        timings[node].latest_start = latest_start
        timings[node].slack = slack
        timings[node].critical = slack <= tolerance
        if timings[node].critical { critical_count += 1usize }
    }
    ret (CpmSummary { duration: duration, critical_count: critical_count, stages: stages }, ok)
}

// Layer by longest dependency depth, then spread peers vertically. Five Rug
// segments per dependency include the arrowhead. Critical links are flagged
// only when they connect zero-slack activities without a timing gap.
fn pert_cpm_network(dependencies: []const CpmDependency, timings: []const CpmTiming, summary: CpmSummary, bounds: geometry.Rect, stage_counts: []usize, stage_used: []usize, boxes: []geometry.Rect, arrows: []Segment, critical_links: []bool) -> (Layout, Layout, err) {
    let n = timings.len
    if n == 0usize { ret (zero, zero, Empty) }
    if summary.stages == 0usize || summary.stages > n || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, zero, Invalid) }
    if stage_counts.len < summary.stages || stage_used.len < summary.stages || boxes.len < n || arrows.len / 5usize < dependencies.len || critical_links.len < dependencies.len { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < summary.stages {
        stage_counts[i] = 0usize
        stage_used[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        if timings[i].stage >= summary.stages { ret (zero, zero, Invalid) }
        stage_counts[timings[i].stage] += 1usize
        i += 1usize
    }
    let cell_width = bounds.width / f32(summary.stages)
    let box_width = cell_width * 0.70
    let box_height = 39.0f32
    if !finite(cell_width) || !finite(box_width) || box_width <= 0.0 || bounds.height < box_height { ret (zero, zero, Invalid) }
    i = 0usize
    while i < n {
        let stage = timings[i].stage
        let slot_height = bounds.height / f32(stage_counts[stage])
        if !finite(slot_height) || slot_height < box_height { ret (zero, zero, TooLarge) }
        let x = bounds.x + (f32(stage) + 0.15) * cell_width
        let y = bounds.y + (f32(stage_used[stage]) + 0.5) * slot_height - box_height * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        stage_used[stage] += 1usize
        i += 1usize
    }
    let tolerance = (summary.duration + 1.0f64) * 0.00000001f64
    i = 0usize
    while i < dependencies.len {
        let link = dependencies[i]
        if link.from >= n || link.to >= n || timings[link.from].stage >= timings[link.to].stage { ret (zero, zero, Invalid) }
        let from = boxes[link.from]
        let to = boxes[link.to]
        let x0 = from.x + from.width
        let x1 = to.x
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let middle = x0 + (x1 - x0) * 0.5
        let head = (x1 - x0) * 0.18
        if !finite(head) || head <= 0.0 { ret (zero, zero, Invalid) }
        let first = i * 5usize
        let tip = Coord { x: x1, y: y1 }
        arrows[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: middle, y: y0 } }
        arrows[first + 1usize] = Segment { from: Coord { x: middle, y: y0 }, to: Coord { x: middle, y: y1 } }
        arrows[first + 2usize] = Segment { from: Coord { x: middle, y: y1 }, to: tip }
        arrows[first + 3usize] = Segment { from: Coord { x: x1 - head, y: y1 - head * 0.7 }, to: tip }
        arrows[first + 4usize] = Segment { from: Coord { x: x1 - head, y: y1 + head * 0.7 }, to: tip }
        let gap = timings[link.to].earliest_start - timings[link.from].earliest_finish
        critical_links[i] = timings[link.from].critical && timings[link.to].critical && gap <= tolerance && gap >= 0.0f64 - tolerance
        i += 1usize
    }
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..n], x_min: 0.0, x_max: f32(summary.stages), y_min: 0.0, y_max: 1.0 }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..dependencies.len * 5usize], bars: zero, x_min: 0.0, x_max: f32(summary.stages), y_min: 0.0, y_max: 1.0 }
    ret (nodes, connectors, ok)
}

// A single ordered material/information flow. Queue and processing intervals
// share a proportional time ladder below equally spaced legible stage boxes.
// PCE uses value-added time (not all processing time) divided by lead time.
fn value_stream_map(steps: []const ValueStreamStep, bounds: geometry.Rect, boxes: []geometry.Rect, arrows: []Segment, process_bars: []geometry.Rect, wait_bars: []geometry.Rect) -> (ValueStreamLayout, err) {
    let n = steps.len
    if n == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if boxes.len < n || arrows.len / 3usize < n - 1usize || process_bars.len < n || wait_bars.len < n { ret (zero, TooLarge) }
    var process_time = 0.0f64
    var value_added_time = 0.0f64
    var wait_time = 0.0f64
    var rolled_yield = 1.0f64
    var i = 0usize
    while i < n {
        let step = steps[i]
        if !finite64(step.process_time) || !finite64(step.value_added_time) || !finite64(step.wait_before) || !finite64(step.good_fraction) || step.process_time <= 0.0f64 || step.value_added_time < 0.0f64 || step.value_added_time > step.process_time || step.wait_before < 0.0f64 || step.good_fraction < 0.0f64 || step.good_fraction > 1.0f64 { ret (zero, Invalid) }
        process_time += step.process_time
        value_added_time += step.value_added_time
        wait_time += step.wait_before
        rolled_yield *= step.good_fraction
        if !finite64(process_time) || !finite64(value_added_time) || !finite64(wait_time) { ret (zero, Invalid) }
        i += 1usize
    }
    let lead_time = process_time + wait_time
    if !finite64(lead_time) || lead_time <= 0.0f64 { ret (zero, Invalid) }
    let cell_width = bounds.width / f32(n)
    let box_width = cell_width * 0.70
    let box_height = bounds.height * 0.29
    let node_y = bounds.y + bounds.height * 0.13
    let timeline_y = bounds.y + bounds.height * 0.70
    let timeline_height = bounds.height * 0.15
    if !finite(cell_width) || !finite(box_width) || !finite(node_y) || !finite(box_height) || !finite(timeline_y) || !finite(timeline_height) || box_width <= 0.0 || box_height <= 0.0 || timeline_height <= 0.0 { ret (zero, Invalid) }
    i = 0usize
    while i < n {
        let x = bounds.x + (f32(i) + 0.15) * cell_width
        if !finite(x) || !finite(x + box_width) { ret (zero, Invalid) }
        boxes[i] = geometry.rect(x, node_y, box_width, box_height)
        if i > 0usize {
            let previous = boxes[i - 1usize]
            let start = Coord { x: previous.x + previous.width, y: node_y + box_height * 0.5 }
            let tip = Coord { x: x, y: start.y }
            let head = (tip.x - start.x) * 0.25
            if !finite(head) || head <= 0.0 { ret (zero, Invalid) }
            let edge = (i - 1usize) * 3usize
            arrows[edge] = Segment { from: start, to: tip }
            arrows[edge + 1usize] = Segment { from: Coord { x: tip.x - head, y: tip.y - head * 0.6 }, to: tip }
            arrows[edge + 2usize] = Segment { from: Coord { x: tip.x - head, y: tip.y + head * 0.6 }, to: tip }
        }
        i += 1usize
    }
    var elapsed = 0.0f64
    var wait_count = 0usize
    i = 0usize
    while i < n {
        let step = steps[i]
        if step.wait_before > 0.0f64 {
            let left = bounds.x + bounds.width * f32(elapsed / lead_time)
            elapsed += step.wait_before
            let right = bounds.x + bounds.width * f32(elapsed / lead_time)
            if !finite(left) || !finite(right) || right <= left { ret (zero, TooLarge) }
            wait_bars[wait_count] = geometry.rect(left, timeline_y, right - left, timeline_height)
            wait_count += 1usize
        }
        let left = bounds.x + bounds.width * f32(elapsed / lead_time)
        elapsed += step.process_time
        let right = bounds.x + bounds.width * f32(elapsed / lead_time)
        if !finite(left) || !finite(right) || right <= left { ret (zero, TooLarge) }
        process_bars[i] = geometry.rect(left, timeline_y, right - left, timeline_height)
        i += 1usize
    }
    let domain_max = 1.0f32
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..n], x_min: 0.0, x_max: domain_max, y_min: 0.0, y_max: 1.0 }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..(n - 1usize) * 3usize], bars: zero, x_min: 0.0, x_max: domain_max, y_min: 0.0, y_max: 1.0 }
    let process = Layout { kind: .Bar, coords: zero, segments: zero, bars: process_bars[..n], x_min: 0.0, x_max: domain_max, y_min: 0.0, y_max: 1.0 }
    let waiting = Layout { kind: .Bar, coords: zero, segments: zero, bars: wait_bars[..wait_count], x_min: 0.0, x_max: domain_max, y_min: 0.0, y_max: 1.0 }
    let summary = ValueStreamSummary { process_time: process_time, value_added_time: value_added_time, wait_time: wait_time, lead_time: lead_time, process_cycle_efficiency: value_added_time / lead_time, rolled_yield: rolled_yield }
    ret (ValueStreamLayout { nodes: nodes, connectors: connectors, process: process, waiting: waiting, summary: summary }, ok)
}

// Side-by-side current/target plans keep their own time ladders. The target
// adds demand-derived takt, a single pacemaker, and explicit flow-control cues.
fn future_value_stream_map(current_steps: []const ValueStreamStep, future_steps: []const ValueStreamStep, links: []const ValueStreamFlow, available_time: f64, customer_demand: f64, pacemaker: usize, current_bounds: geometry.Rect, future_bounds: geometry.Rect, work: *FutureValueStreamWork) -> (FutureValueStreamLayout, err) {
    if current_steps.len == 0usize || future_steps.len == 0usize { ret (zero, Empty) }
    if links.len != future_steps.len - 1usize || pacemaker >= future_steps.len || !finite64(available_time) || !finite64(customer_demand) || available_time <= 0.0f64 || customer_demand <= 0.0f64 { ret (zero, Invalid) }
    let takt = available_time / customer_demand
    if !finite64(takt) || takt <= 0.0f64 { ret (zero, Invalid) }
    if work.fifo_cues.len < links.len || work.pull_cues.len < links.len || work.over_takt.len < future_steps.len || work.pacemaker.len < 1usize { ret (zero, TooLarge) }
    let (current, current_error) = value_stream_map(current_steps, current_bounds, work.current.boxes, work.current.arrows, work.current.process_bars, work.current.wait_bars)
    if current_error != ok { ret (zero, current_error) }
    let (future, future_error) = value_stream_map(future_steps, future_bounds, work.future.boxes, work.future.arrows, work.future.process_bars, work.future.wait_bars)
    if future_error != ok { ret (zero, future_error) }
    var fifo_count = 0usize
    var pull_count = 0usize
    var i = 0usize
    while i < links.len {
        let segment = future.connectors.segments[i * 3usize]
        let center = (segment.from.x + segment.to.x) * 0.5f32
        let y = segment.from.y
        if links[i] == .Fifo {
            work.fifo_cues[fifo_count] = geometry.rect(center - 3.0f32, y - 3.0f32, 6.0f32, 6.0f32)
            fifo_count += 1usize
        } else if links[i] == .Pull {
            work.pull_cues[pull_count] = geometry.rect(center - 3.0f32, y - 3.0f32, 6.0f32, 6.0f32)
            pull_count += 1usize
        }
        i += 1usize
    }
    var over_count = 0usize
    i = 0usize
    while i < future_steps.len {
        if future_steps[i].process_time > takt {
            let box = future.nodes.bars[i]
            work.over_takt[over_count] = geometry.rect(box.x, box.y + box.height - 3.0f32, box.width, 3.0f32)
            over_count += 1usize
        }
        i += 1usize
    }
    let pacemaker_box = future.nodes.bars[pacemaker]
    work.pacemaker[0usize] = geometry.rect(pacemaker_box.x, pacemaker_box.y - 5.0f32, pacemaker_box.width, 3.0f32)
    let domain = 1.0f32
    let fifo = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.fifo_cues[..fifo_count], x_min: 0.0, x_max: domain, y_min: 0.0, y_max: domain }
    let pull = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.pull_cues[..pull_count], x_min: 0.0, x_max: domain, y_min: 0.0, y_max: domain }
    let over_takt = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.over_takt[..over_count], x_min: 0.0, x_max: domain, y_min: 0.0, y_max: domain }
    let pacemaker_marks = Layout { kind: .Bar, coords: zero, segments: zero, bars: work.pacemaker[..1usize], x_min: 0.0, x_max: domain, y_min: 0.0, y_max: domain }
    ret (FutureValueStreamLayout {
        current: current, future: future, fifo: fifo, pull: pull, over_takt: over_takt, pacemaker: pacemaker_marks,
        takt_time: takt, lead_reduction: current.summary.lead_time - future.summary.lead_time,
        pce_gain: future.summary.process_cycle_efficiency - current.summary.process_cycle_efficiency,
        yield_gain: future.summary.rolled_yield - current.summary.rolled_yield,
    }, ok)
}

// Fixed SIPOC order: supplier, input, process, output, customer. Entries keep
// input order within their column; the caller supplies text and palette.
fn sipoc(entries: []const SipocEntry, bounds: geometry.Rect, gutter: f32, padding: f32, header_height: f32, card_gap: f32, columns: []geometry.Rect, headers: []geometry.Rect, cards: []geometry.Rect, arrows: []Segment, counts: []usize, used: []usize) -> (SipocLayout, err) {
    if entries.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(gutter) || gutter <= 0.0 || !finite(padding) || padding < 0.0 || !finite(header_height) || header_height <= 0.0 || !finite(card_gap) || card_gap < 0.0 { ret (zero, Invalid) }
    if columns.len < 5usize || headers.len < 5usize || cards.len < entries.len || arrows.len < 12usize || counts.len < 5usize || used.len < 5usize { ret (zero, TooLarge) }
    let column_width = (bounds.width - 4.0 * gutter) / 5.0
    let card_width = column_width - 2.0 * padding
    let body_height = bounds.height - header_height - 2.0 * padding
    if !finite(column_width) || !finite(card_width) || !finite(body_height) || column_width <= 0.0 || card_width <= 0.0 || body_height <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < 5usize {
        counts[i] = 0usize
        used[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        if entries[i].column >= 5usize { ret (zero, Invalid) }
        counts[entries[i].column] += 1usize
        i += 1usize
    }
    var max_rows = 0usize
    i = 0usize
    while i < 5usize {
        if counts[i] > max_rows { max_rows = counts[i] }
        i += 1usize
    }
    let card_height = (body_height - card_gap * f32(max_rows - 1usize)) / f32(max_rows)
    if !finite(card_height) || card_height < 12.0 { ret (zero, TooLarge) }
    i = 0usize
    while i < 5usize {
        let x = bounds.x + f32(i) * (column_width + gutter)
        if !finite(x) || !finite(x + column_width) { ret (zero, Invalid) }
        columns[i] = geometry.rect(x, bounds.y, column_width, bounds.height)
        headers[i] = geometry.rect(x, bounds.y, column_width, header_height)
        if i > 0usize {
            let before = headers[i - 1usize]
            let start = Coord { x: before.x + before.width, y: bounds.y + header_height * 0.5 }
            let tip = Coord { x: x, y: start.y }
            let head = gutter * 0.3
            let first = (i - 1usize) * 3usize
            arrows[first] = Segment { from: start, to: tip }
            arrows[first + 1usize] = Segment { from: Coord { x: tip.x - head, y: tip.y - head * 0.7 }, to: tip }
            arrows[first + 2usize] = Segment { from: Coord { x: tip.x - head, y: tip.y + head * 0.7 }, to: tip }
        }
        i += 1usize
    }
    i = 0usize
    while i < entries.len {
        let column = entries[i].column
        let x = columns[column].x + padding
        let y = bounds.y + header_height + padding + f32(used[column]) * (card_height + card_gap)
        if !finite(y) || !finite(y + card_height) { ret (zero, Invalid) }
        cards[i] = geometry.rect(x, y, card_width, card_height)
        used[column] += 1usize
        i += 1usize
    }
    let bands = Layout { kind: .Bar, coords: zero, segments: zero, bars: columns[..5usize], x_min: 0.0, x_max: 5.0, y_min: 0.0, y_max: f32(max_rows) }
    let heads = Layout { kind: .Bar, coords: zero, segments: zero, bars: headers[..5usize], x_min: 0.0, x_max: 5.0, y_min: 0.0, y_max: f32(max_rows) }
    let items = Layout { kind: .Bar, coords: zero, segments: zero, bars: cards[..entries.len], x_min: 0.0, x_max: 5.0, y_min: 0.0, y_max: f32(max_rows) }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..12usize], bars: zero, x_min: 0.0, x_max: 5.0, y_min: 0.0, y_max: f32(max_rows) }
    ret (SipocLayout { bands: bands, headers: heads, cards: items, connectors: connectors, max_rows: max_rows }, ok)
}

// A rooted tree, not a general DAG: node zero is the root and every other
// node has exactly one parent. Chance-edge probabilities sum to one. A choice
// selects the largest expected child value, breaking ties by input edge order.
fn decision_tree_values(nodes: []const DecisionNode, edges: []const DecisionEdge, values: []DecisionValue, work: DecisionTreeWork) -> (DecisionTreeSummary, err) {
    let n = nodes.len
    if n == 0usize { ret (zero, Empty) }
    if values.len < n || work.indegree.len < n || work.head.len < n || work.order.len < n || work.next.len < edges.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if !finite64(nodes[i].payoff) { ret (zero, Invalid) }
        if nodes[i].kind != .Outcome && nodes[i].payoff != 0.0f64 { ret (zero, Invalid) }
        values[i] = DecisionValue { expected: 0.0f64, selected_edge: edges.len, depth: 0usize, leaf_count: 0usize, leaf_start: 0usize }
        work.indegree[i] = 0usize
        work.head[i] = 0usize
        i += 1usize
    }
    i = edges.len
    while i > 0usize {
        i -= 1usize
        let link = edges[i]
        if link.from >= n || link.to >= n || link.from == link.to || !finite64(link.probability) || link.probability < 0.0f64 || link.probability > 1.0f64 || nodes[link.from].kind == .Outcome || (nodes[link.from].kind == .Choice && link.probability != 0.0f64) { ret (zero, Invalid) }
        work.indegree[link.to] += 1usize
        if work.indegree[link.to] > 1usize { ret (zero, Invalid) }
        work.next[i] = work.head[link.from]
        work.head[link.from] = i + 1usize
    }
    if work.indegree[0usize] != 0usize { ret (zero, Invalid) }
    i = 1usize
    while i < n {
        if work.indegree[i] != 1usize { ret (zero, Invalid) }
        i += 1usize
    }
    work.order[0usize] = 0usize
    var front = 0usize
    var tail = 1usize
    var depth = 1usize
    while front < tail {
        let node = work.order[front]
        if nodes[node].kind != .Outcome && work.head[node] == 0usize { ret (zero, Invalid) }
        var edge = work.head[node]
        while edge != 0usize {
            let child = edges[edge - 1usize].to
            values[child].depth = values[node].depth + 1usize
            if values[child].depth + 1usize > depth { depth = values[child].depth + 1usize }
            work.order[tail] = child
            tail += 1usize
            edge = work.next[edge - 1usize]
        }
        front += 1usize
    }
    if tail != n { ret (zero, Invalid) }
    i = n
    while i > 0usize {
        i -= 1usize
        let node = work.order[i]
        if nodes[node].kind == .Outcome {
            values[node].expected = nodes[node].payoff
            values[node].leaf_count = 1usize
        } else {
            var edge = work.head[node]
            var probability_sum = 0.0f64
            var best = 0.0f64
            while edge != 0usize {
                let index = edge - 1usize
                let child = edges[index].to
                let candidate = values[child].expected
                values[node].leaf_count += values[child].leaf_count
                if nodes[node].kind == .Chance {
                    probability_sum += edges[index].probability
                    values[node].expected += edges[index].probability * candidate
                } else if values[node].selected_edge == edges.len || candidate > best || (candidate == best && index < values[node].selected_edge) {
                    best = candidate
                    values[node].selected_edge = index
                    values[node].expected = candidate
                }
                edge = work.next[index]
            }
            if nodes[node].kind == .Chance && (probability_sum < 0.999999f64 || probability_sum > 1.000001f64) { ret (zero, Invalid) }
            if !finite64(values[node].expected) || values[node].leaf_count == 0usize { ret (zero, Invalid) }
        }
    }
    i = 0usize
    while i < n {
        let node = work.order[i]
        var start = values[node].leaf_start
        var edge = work.head[node]
        while edge != 0usize {
            let child = edges[edge - 1usize].to
            values[child].leaf_start = start
            start += values[child].leaf_count
            edge = work.next[edge - 1usize]
        }
        i += 1usize
    }
    ret (DecisionTreeSummary { expected: values[0usize].expected, depth: depth, leaves: values[0usize].leaf_count }, ok)
}

// Leaf intervals reserve equal vertical area. Parent centers track the middle
// of their descendant interval, while depths give non-overlapping columns.
fn decision_tree_layout(nodes: []const DecisionNode, edges: []const DecisionEdge, values: []const DecisionValue, summary: DecisionTreeSummary, bounds: geometry.Rect, boxes: []geometry.Rect, arrows: []Segment, chosen: []bool) -> (Layout, Layout, err) {
    let n = nodes.len
    if n == 0usize { ret (zero, zero, Empty) }
    if values.len < n || summary.depth == 0usize || summary.leaves == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, zero, Invalid) }
    if boxes.len < n || arrows.len / 5usize < edges.len || chosen.len < edges.len { ret (zero, zero, TooLarge) }
    let cell_width = bounds.width / f32(summary.depth)
    let leaf_height = bounds.height / f32(summary.leaves)
    let box_width = cell_width * 0.58
    let box_height = leaf_height * 0.58
    if !finite(cell_width) || !finite(leaf_height) || !finite(box_width) || !finite(box_height) || box_width <= 0.0 || leaf_height < 19.0 { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < n {
        let node = values[i]
        if node.depth >= summary.depth || node.leaf_count == 0usize || node.leaf_start + node.leaf_count > summary.leaves { ret (zero, zero, Invalid) }
        let x = bounds.x + (f32(node.depth) + 0.21) * cell_width
        let y = bounds.y + (f32(node.leaf_start) + f32(node.leaf_count) * 0.5) * leaf_height - box_height * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        i += 1usize
    }
    i = 0usize
    while i < edges.len {
        let link = edges[i]
        if link.from >= n || link.to >= n || values[link.from].depth + 1usize != values[link.to].depth { ret (zero, zero, Invalid) }
        let from = boxes[link.from]
        let to = boxes[link.to]
        let x0 = from.x + from.width
        let x1 = to.x
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let middle = x0 + (x1 - x0) * 0.5
        let head = (x1 - x0) * 0.16
        if !finite(head) || head <= 0.0 { ret (zero, zero, Invalid) }
        let first = i * 5usize
        let tip = Coord { x: x1, y: y1 }
        arrows[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: middle, y: y0 } }
        arrows[first + 1usize] = Segment { from: Coord { x: middle, y: y0 }, to: Coord { x: middle, y: y1 } }
        arrows[first + 2usize] = Segment { from: Coord { x: middle, y: y1 }, to: tip }
        arrows[first + 3usize] = Segment { from: Coord { x: x1 - head, y: y1 - head * 0.7 }, to: tip }
        arrows[first + 4usize] = Segment { from: Coord { x: x1 - head, y: y1 + head * 0.7 }, to: tip }
        chosen[i] = nodes[link.from].kind == .Choice && values[link.from].selected_edge == i
        i += 1usize
    }
    let node_layout = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..n], x_min: 0.0, x_max: f32(summary.depth), y_min: 0.0, y_max: f32(summary.leaves) }
    let connector_layout = Layout { kind: .Rug, coords: zero, segments: arrows[..edges.len * 5usize], bars: zero, x_min: 0.0, x_max: f32(summary.depth), y_min: 0.0, y_max: f32(summary.leaves) }
    ret (node_layout, connector_layout, ok)
}

// A single-root, solid-line reporting tree. Siblings follow link input order,
// and each subtree reserves one horizontal slot per terminal report.
fn org_chart(node_count: usize, links: []const OrgLink, bounds: geometry.Rect, placements: []OrgPlacement, work: OrgWork, boxes: []geometry.Rect, connectors: []Segment) -> (OrgLayout, err) {
    if node_count == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if placements.len < node_count || work.indegree.len < node_count || work.head.len < node_count || work.order.len < node_count || work.next.len < links.len || boxes.len < node_count || connectors.len / 3usize < links.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < node_count {
        placements[i] = OrgPlacement { depth: 0usize, leaf_start: 0usize, leaf_count: 0usize, direct_reports: 0usize }
        work.indegree[i] = 0usize
        work.head[i] = 0usize
        i += 1usize
    }
    i = links.len
    while i > 0usize {
        i -= 1usize
        let link = links[i]
        if link.manager >= node_count || link.report >= node_count || link.manager == link.report { ret (zero, Invalid) }
        work.indegree[link.report] += 1usize
        if work.indegree[link.report] > 1usize { ret (zero, Invalid) }
        placements[link.manager].direct_reports += 1usize
        work.next[i] = work.head[link.manager]
        work.head[link.manager] = i + 1usize
    }
    if work.indegree[0usize] != 0usize { ret (zero, Invalid) }
    i = 1usize
    while i < node_count {
        if work.indegree[i] != 1usize { ret (zero, Invalid) }
        i += 1usize
    }
    work.order[0usize] = 0usize
    var front = 0usize
    var tail = 1usize
    var levels = 1usize
    while front < tail {
        let manager = work.order[front]
        var edge = work.head[manager]
        while edge != 0usize {
            let report = links[edge - 1usize].report
            placements[report].depth = placements[manager].depth + 1usize
            if placements[report].depth + 1usize > levels { levels = placements[report].depth + 1usize }
            work.order[tail] = report
            tail += 1usize
            edge = work.next[edge - 1usize]
        }
        front += 1usize
    }
    if tail != node_count { ret (zero, Invalid) }
    i = node_count
    while i > 0usize {
        i -= 1usize
        let manager = work.order[i]
        if placements[manager].direct_reports == 0usize { placements[manager].leaf_count = 1usize }
        var edge = work.head[manager]
        while edge != 0usize {
            placements[manager].leaf_count += placements[links[edge - 1usize].report].leaf_count
            edge = work.next[edge - 1usize]
        }
    }
    let leaves = placements[0usize].leaf_count
    i = 0usize
    while i < node_count {
        let manager = work.order[i]
        var start = placements[manager].leaf_start
        var edge = work.head[manager]
        while edge != 0usize {
            let report = links[edge - 1usize].report
            placements[report].leaf_start = start
            start += placements[report].leaf_count
            edge = work.next[edge - 1usize]
        }
        i += 1usize
    }
    let leaf_width = bounds.width / f32(leaves)
    let row_height = bounds.height / f32(levels)
    var box_width = leaf_width * 0.72
    if box_width > 118.0 { box_width = 118.0 }
    var box_height = row_height * 0.44
    if box_height > 38.0 { box_height = 38.0 }
    if !finite(leaf_width) || !finite(row_height) || leaf_width < 38.0 || row_height < 30.0 || !finite(box_width) || !finite(box_height) { ret (zero, TooLarge) }
    i = 0usize
    while i < node_count {
        let place = placements[i]
        let center = bounds.x + (f32(place.leaf_start) + f32(place.leaf_count) * 0.5) * leaf_width
        let x = center - box_width * 0.5
        let y = bounds.y + f32(place.depth) * row_height + (row_height - box_height) * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        i += 1usize
    }
    i = 0usize
    while i < links.len {
        let from = boxes[links[i].manager]
        let to = boxes[links[i].report]
        let x0 = from.x + from.width * 0.5
        let x1 = to.x + to.width * 0.5
        let y0 = from.y + from.height
        let y1 = to.y
        let mid_y = y0 + (y1 - y0) * 0.5
        if !finite(mid_y) || y1 <= y0 { ret (zero, Invalid) }
        let first = i * 3usize
        connectors[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: x0, y: mid_y } }
        connectors[first + 1usize] = Segment { from: Coord { x: x0, y: mid_y }, to: Coord { x: x1, y: mid_y } }
        connectors[first + 2usize] = Segment { from: Coord { x: x1, y: mid_y }, to: Coord { x: x1, y: y1 } }
        i += 1usize
    }
    let people = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..node_count], x_min: 0.0, x_max: f32(leaves), y_min: 0.0, y_max: f32(levels) }
    let reporting = Layout { kind: .Rug, coords: zero, segments: connectors[..links.len * 3usize], bars: zero, x_min: 0.0, x_max: f32(leaves), y_min: 0.0, y_max: f32(levels) }
    ret (OrgLayout { nodes: people, connectors: reporting, levels: levels, leaves: leaves }, ok)
}

// Longest-path ranks give every edge a left-to-right direction. Kahn's pass
// handles multiple sources, merges and disconnected components; cycles refuse.
fn dependency_graph(node_count: usize, links: []const DependencyLink, bounds: geometry.Rect, work: DependencyWork, boxes: []geometry.Rect, arrows: []Segment) -> (DependencyLayout, err) {
    if node_count == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if work.indegree.len < node_count || work.head.len < node_count || work.order.len < node_count || work.stage.len < node_count || work.stage_counts.len < node_count || work.stage_used.len < node_count || work.next.len < links.len || boxes.len < node_count || arrows.len / 5usize < links.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < node_count {
        work.indegree[i] = 0usize
        work.head[i] = 0usize
        work.stage[i] = 0usize
        work.stage_counts[i] = 0usize
        work.stage_used[i] = 0usize
        i += 1usize
    }
    i = links.len
    while i > 0usize {
        i -= 1usize
        let link = links[i]
        if link.from >= node_count || link.to >= node_count || link.from == link.to { ret (zero, Invalid) }
        work.indegree[link.to] += 1usize
        work.next[i] = work.head[link.from]
        work.head[link.from] = i + 1usize
    }
    var tail = 0usize
    var sources = 0usize
    i = 0usize
    while i < node_count {
        if work.indegree[i] == 0usize {
            work.order[tail] = i
            tail += 1usize
            sources += 1usize
        }
        i += 1usize
    }
    var front = 0usize
    var stages = 1usize
    while front < tail {
        let node = work.order[front]
        var edge = work.head[node]
        while edge != 0usize {
            let to = links[edge - 1usize].to
            let next_stage = work.stage[node] + 1usize
            if next_stage > work.stage[to] { work.stage[to] = next_stage }
            if next_stage + 1usize > stages { stages = next_stage + 1usize }
            work.indegree[to] -= 1usize
            if work.indegree[to] == 0usize {
                work.order[tail] = to
                tail += 1usize
            }
            edge = work.next[edge - 1usize]
        }
        front += 1usize
    }
    if tail != node_count { ret (zero, Invalid) }
    i = 0usize
    while i < node_count {
        work.stage_counts[work.stage[i]] += 1usize
        i += 1usize
    }
    let cell_width = bounds.width / f32(stages)
    var box_width = cell_width * 0.66
    if box_width > 96.0 { box_width = 96.0 }
    let box_height = 30.0f32
    if !finite(cell_width) || !finite(box_width) || box_width < 32.0 { ret (zero, TooLarge) }
    i = 0usize
    while i < node_count {
        let rank = work.stage[i]
        let slot_height = bounds.height / f32(work.stage_counts[rank])
        if !finite(slot_height) || slot_height < box_height + 6.0 { ret (zero, TooLarge) }
        let x = bounds.x + (f32(rank) + 0.5) * cell_width - box_width * 0.5
        let y = bounds.y + (f32(work.stage_used[rank]) + 0.5) * slot_height - box_height * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        work.stage_used[rank] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < links.len {
        let from = boxes[links[i].from]
        let to = boxes[links[i].to]
        let x0 = from.x + from.width
        let x1 = to.x
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let mid = x0 + (x1 - x0) * 0.5
        var head = (x1 - x0) * 0.18
        if head > 7.0 { head = 7.0 }
        if !finite(mid) || !finite(head) || head <= 0.0 { ret (zero, TooLarge) }
        let tip = Coord { x: x1, y: y1 }
        let first = i * 5usize
        arrows[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: mid, y: y0 } }
        arrows[first + 1usize] = Segment { from: Coord { x: mid, y: y0 }, to: Coord { x: mid, y: y1 } }
        arrows[first + 2usize] = Segment { from: Coord { x: mid, y: y1 }, to: tip }
        arrows[first + 3usize] = Segment { from: Coord { x: x1 - head, y: y1 - head * 0.7 }, to: tip }
        arrows[first + 4usize] = Segment { from: Coord { x: x1 - head, y: y1 + head * 0.7 }, to: tip }
        i += 1usize
    }
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..node_count], x_min: 0.0, x_max: f32(stages), y_min: 0.0, y_max: 1.0 }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..links.len * 5usize], bars: zero, x_min: 0.0, x_max: f32(stages), y_min: 0.0, y_max: 1.0 }
    ret (DependencyLayout { nodes: nodes, connectors: connectors, stages: stages, sources: sources }, ok)
}

fn flow_port(box: geometry.Rect, port: FlowPort) -> Coord {
    if port == .Top { ret Coord { x: box.x + box.width * 0.5, y: box.y } }
    if port == .Right { ret Coord { x: box.x + box.width, y: box.y + box.height * 0.5 } }
    if port == .Bottom { ret Coord { x: box.x + box.width * 0.5, y: box.y + box.height } }
    ret Coord { x: box.x, y: box.y + box.height * 0.5 }
}

// Explicit node centers allow return loops. Links use opposing ports and must
// travel outward from their exit before entering the next shape.
fn flowchart(nodes: []const FlowNode, links: []const FlowLink, bounds: geometry.Rect, node_width: f32, node_height: f32, boxes: []geometry.Rect, outlines: []Coord, shapes: []Layout, arrows: []Segment) -> (FlowLayout, err) {
    if nodes.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(node_width) || !finite(node_height) || node_width < 20.0 || node_height < 18.0 { ret (zero, Invalid) }
    if boxes.len < nodes.len || outlines.len / 8usize < nodes.len || shapes.len < nodes.len || arrows.len / 5usize < links.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < nodes.len {
        let center = nodes[i].center
        if !finite(center.x) || !finite(center.y) { ret (zero, Invalid) }
        let x = center.x - node_width * 0.5
        let y = center.y - node_height * 0.5
        if !finite(x) || !finite(y) || x < bounds.x || y < bounds.y || x + node_width > bounds.x + bounds.width || y + node_height > bounds.y + bounds.height { ret (zero, Invalid) }
        boxes[i] = geometry.rect(x, y, node_width, node_height)
        var earlier = 0usize
        while earlier < i {
            let other = boxes[earlier]
            if x < other.x + other.width && x + node_width > other.x && y < other.y + other.height && y + node_height > other.y { ret (zero, Invalid) }
            earlier += 1usize
        }
        let first = i * 8usize
        if nodes[i].kind == .Process {
            shapes[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else if nodes[i].kind == .Decision {
            outlines[first] = Coord { x: center.x, y: y }
            outlines[first + 1usize] = Coord { x: x + node_width, y: center.y }
            outlines[first + 2usize] = Coord { x: center.x, y: y + node_height }
            outlines[first + 3usize] = Coord { x: x, y: center.y }
            shapes[i] = Layout { kind: .Area, coords: outlines[first..first + 4usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let inset = node_height * 0.32
            outlines[first] = Coord { x: x + inset, y: y }
            outlines[first + 1usize] = Coord { x: x + node_width - inset, y: y }
            outlines[first + 2usize] = Coord { x: x + node_width, y: y + inset }
            outlines[first + 3usize] = Coord { x: x + node_width, y: y + node_height - inset }
            outlines[first + 4usize] = Coord { x: x + node_width - inset, y: y + node_height }
            outlines[first + 5usize] = Coord { x: x + inset, y: y + node_height }
            outlines[first + 6usize] = Coord { x: x, y: y + node_height - inset }
            outlines[first + 7usize] = Coord { x: x, y: y + inset }
            shapes[i] = Layout { kind: .Area, coords: outlines[first..first + 8usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        i += 1usize
    }
    i = 0usize
    while i < links.len {
        let link = links[i]
        if link.from >= nodes.len || link.to >= nodes.len || link.from == link.to { ret (zero, Invalid) }
        let start = flow_port(boxes[link.from], link.exit)
        let tip = flow_port(boxes[link.to], link.entry)
        let vertical = (link.exit == .Top && link.entry == .Bottom) || (link.exit == .Bottom && link.entry == .Top)
        let horizontal = (link.exit == .Left && link.entry == .Right) || (link.exit == .Right && link.entry == .Left)
        if !vertical && !horizontal { ret (zero, Invalid) }
        let first = i * 5usize
        var head = 6.0f32
        if vertical {
            let gap = tip.y - start.y
            if (link.exit == .Bottom && gap <= 2.0) || (link.exit == .Top && gap >= -2.0) { ret (zero, Invalid) }
            var distance = gap
            if distance < 0.0 { distance = -distance }
            if head > distance * 0.25 { head = distance * 0.25 }
            let mid = start.y + gap * 0.5
            arrows[first] = Segment { from: start, to: Coord { x: start.x, y: mid } }
            arrows[first + 1usize] = Segment { from: Coord { x: start.x, y: mid }, to: Coord { x: tip.x, y: mid } }
            arrows[first + 2usize] = Segment { from: Coord { x: tip.x, y: mid }, to: tip }
            var offset = head
            if link.entry == .Top { offset = -head }
            arrows[first + 3usize] = Segment { from: Coord { x: tip.x - head * 0.7, y: tip.y + offset }, to: tip }
            arrows[first + 4usize] = Segment { from: Coord { x: tip.x + head * 0.7, y: tip.y + offset }, to: tip }
        } else {
            let gap = tip.x - start.x
            if (link.exit == .Right && gap <= 2.0) || (link.exit == .Left && gap >= -2.0) { ret (zero, Invalid) }
            var distance = gap
            if distance < 0.0 { distance = -distance }
            if head > distance * 0.25 { head = distance * 0.25 }
            let mid = start.x + gap * 0.5
            arrows[first] = Segment { from: start, to: Coord { x: mid, y: start.y } }
            arrows[first + 1usize] = Segment { from: Coord { x: mid, y: start.y }, to: Coord { x: mid, y: tip.y } }
            arrows[first + 2usize] = Segment { from: Coord { x: mid, y: tip.y }, to: tip }
            var offset = head
            if link.entry == .Left { offset = -head }
            arrows[first + 3usize] = Segment { from: Coord { x: tip.x + offset, y: tip.y - head * 0.7 }, to: tip }
            arrows[first + 4usize] = Segment { from: Coord { x: tip.x + offset, y: tip.y + head * 0.7 }, to: tip }
        }
        i += 1usize
    }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..links.len * 5usize], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (FlowLayout { nodes: shapes[..nodes.len], connectors: connectors }, ok)
}

// No matching event leaves the machine in place. Duplicate (state,event)
// transitions are an error, regardless of their destination.
fn state_machine_step(state_count: usize, current: usize, event: usize, transitions: []const MachineTransition) -> (usize, bool, err) {
    if state_count == 0usize { ret (0usize, false, Empty) }
    if current >= state_count { ret (0usize, false, Invalid) }
    var next = current
    var fired = false
    var i = 0usize
    while i < transitions.len {
        let transition = transitions[i]
        if transition.from >= state_count || transition.to >= state_count { ret (0usize, false, Invalid) }
        if transition.from == current && transition.event == event {
            if fired { ret (0usize, false, Invalid) }
            next = transition.to
            fired = true
        }
        i += 1usize
    }
    ret (next, fired, ok)
}

// Explicit centers keep cycles and self loops; circles and edge labels are
// caller-owned geometry. A single initial state and deterministic events are
// required, while any number of final states is allowed.
fn state_machine(states: []const MachineState, transitions: []const MachineTransition, events: []const str, bounds: geometry.Rect, radius: f32, outlines: []Coord, shapes: []Layout, arrows: []Segment, ring_segments: []Segment, start_segments: []Segment, event_labels: []Label) -> (MachineLayout, err) {
    if states.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(radius) || radius < 12.0 { ret (zero, Invalid) }
    if outlines.len / 24usize < states.len || shapes.len < states.len || arrows.len / 5usize < transitions.len || event_labels.len < transitions.len || start_segments.len < 3usize { ret (zero, TooLarge) }
    var initial = states.len
    var final_count = 0usize
    var i = 0usize
    while i < states.len {
        let state = states[i]
        if !finite(state.center.x) || !finite(state.center.y) || state.center.x - radius < bounds.x || state.center.x + radius > bounds.x + bounds.width || state.center.y - radius < bounds.y || state.center.y + radius > bounds.y + bounds.height { ret (zero, Invalid) }
        if state.initial {
            if initial != states.len { ret (zero, Invalid) }
            initial = i
        }
        if state.final { final_count += 1usize }
        var earlier = 0usize
        while earlier < i {
            let dx = f64(state.center.x) - f64(states[earlier].center.x)
            let dy = f64(state.center.y) - f64(states[earlier].center.y)
            let minimum = f64(radius * 2.0 + 8.0)
            if dx * dx + dy * dy < minimum * minimum { ret (zero, Invalid) }
            earlier += 1usize
        }
        let first = i * 24usize
        var point = 0usize
        while point < 24usize {
            let angle = 6.283185307179586f64 * f64(point) / 24.0f64
            outlines[first + point] = Coord { x: state.center.x + radius * f32(math.cos[f64](angle)), y: state.center.y + radius * f32(math.sin[f64](angle)) }
            point += 1usize
        }
        shapes[i] = Layout { kind: .Area, coords: outlines[first..first + 24usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    if initial == states.len { ret (zero, Invalid) }
    if ring_segments.len / 24usize < final_count { ret (zero, TooLarge) }
    let initial_center = states[initial].center
    if initial_center.x - radius - 19.0 < bounds.x { ret (zero, TooLarge) }
    let start = Coord { x: initial_center.x - radius - 19.0, y: initial_center.y }
    let tip = Coord { x: initial_center.x - radius, y: initial_center.y }
    start_segments[0usize] = Segment { from: start, to: tip }
    start_segments[1usize] = Segment { from: Coord { x: tip.x - 6.0, y: tip.y - 4.0 }, to: tip }
    start_segments[2usize] = Segment { from: Coord { x: tip.x - 6.0, y: tip.y + 4.0 }, to: tip }
    var rings_used = 0usize
    i = 0usize
    while i < states.len {
        if states[i].final {
            let center = states[i].center
            var point = 0usize
            while point < 24usize {
                let first_angle = 6.283185307179586f64 * f64(point) / 24.0f64
                let second_angle = 6.283185307179586f64 * f64((point + 1usize) % 24usize) / 24.0f64
                let inner = radius * 0.78
                let from = Coord { x: center.x + inner * f32(math.cos[f64](first_angle)), y: center.y + inner * f32(math.sin[f64](first_angle)) }
                let to = Coord { x: center.x + inner * f32(math.cos[f64](second_angle)), y: center.y + inner * f32(math.sin[f64](second_angle)) }
                ring_segments[rings_used] = Segment { from: from, to: to }
                rings_used += 1usize
                point += 1usize
            }
        }
        i += 1usize
    }
    var arrows_used = 0usize
    i = 0usize
    while i < transitions.len {
        let transition = transitions[i]
        if transition.from >= states.len || transition.to >= states.len || transition.event >= events.len { ret (zero, Invalid) }
        var earlier = 0usize
        while earlier < i {
            if transitions[earlier].from == transition.from && transitions[earlier].event == transition.event { ret (zero, Invalid) }
            earlier += 1usize
        }
        let from = states[transition.from].center
        let to = states[transition.to].center
        if transition.from == transition.to {
            let top = from.y - radius - 18.0
            if top < bounds.y { ret (zero, TooLarge) }
            let loop_start = Coord { x: from.x + radius * 0.55, y: from.y - radius * 0.80 }
            let loop_end = Coord { x: from.x - radius * 0.55, y: from.y - radius * 0.80 }
            let upper_right = Coord { x: loop_start.x, y: top }
            let upper_left = Coord { x: loop_end.x, y: top }
            arrows[arrows_used] = Segment { from: loop_start, to: upper_right }
            arrows[arrows_used + 1usize] = Segment { from: upper_right, to: upper_left }
            arrows[arrows_used + 2usize] = Segment { from: upper_left, to: loop_end }
            arrows[arrows_used + 3usize] = Segment { from: Coord { x: loop_end.x - 4.0, y: loop_end.y - 6.0 }, to: loop_end }
            arrows[arrows_used + 4usize] = Segment { from: Coord { x: loop_end.x + 4.0, y: loop_end.y - 6.0 }, to: loop_end }
            arrows_used += 5usize
            event_labels[i] = Label { text: events[transition.event], anchor: Coord { x: from.x, y: top - 5.0 }, align: .Center }
        } else {
            let dx = f64(to.x) - f64(from.x)
            let dy = f64(to.y) - f64(from.y)
            let distance = math.sqrt[f64](dx * dx + dy * dy)
            if !finite64(distance) || distance <= f64(radius * 2.0 + 8.0) { ret (zero, Invalid) }
            let ux = f32(dx / distance)
            let uy = f32(dy / distance)
            let edge_start = Coord { x: from.x + ux * radius, y: from.y + uy * radius }
            let edge_end = Coord { x: to.x - ux * radius, y: to.y - uy * radius }
            arrows[arrows_used] = Segment { from: edge_start, to: edge_end }
            arrows[arrows_used + 1usize] = Segment { from: Coord { x: edge_end.x - ux * 7.0 - uy * 4.0, y: edge_end.y - uy * 7.0 + ux * 4.0 }, to: edge_end }
            arrows[arrows_used + 2usize] = Segment { from: Coord { x: edge_end.x - ux * 7.0 + uy * 4.0, y: edge_end.y - uy * 7.0 - ux * 4.0 }, to: edge_end }
            arrows_used += 3usize
            event_labels[i] = Label { text: events[transition.event], anchor: Coord { x: (from.x + to.x) * 0.5 + uy * 10.0, y: (from.y + to.y) * 0.5 - ux * 10.0 }, align: .Center }
        }
        i += 1usize
    }
    let routes = Layout { kind: .Rug, coords: zero, segments: arrows[..arrows_used], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let initial_route = Layout { kind: .Rug, coords: zero, segments: start_segments[..3usize], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let finals = Layout { kind: .Rug, coords: zero, segments: ring_segments[..rings_used], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (MachineLayout { states: shapes[..states.len], transitions: routes, initial_marker: initial_route, final_rings: finals, event_labels: event_labels[..transitions.len] }, ok)
}

// Ordered message rows stay independent of graph topology. Participants own
// header/lifeline slots; calls, returns and async arrows are separate layers.
fn sequence_diagram(participants: []const str, messages: []const SequenceMessage, activations: []const SequenceActivation, bounds: geometry.Rect, header_boxes: []geometry.Rect, lifeline_segments: []Segment, activation_boxes: []geometry.Rect, message_segments: []Segment, message_layers: []Layout, message_labels: []Label) -> (SequenceLayout, err) {
    if participants.len == 0usize || messages.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if header_boxes.len < participants.len || lifeline_segments.len / 10usize < participants.len || activation_boxes.len < activations.len || message_segments.len / 8usize < messages.len || message_layers.len < messages.len || message_labels.len < messages.len { ret (zero, TooLarge) }
    let cell_width = bounds.width / f32(participants.len)
    let row_height = (bounds.height - 38.0) / f32(messages.len)
    var header_width = cell_width * 0.74
    if header_width > 92.0 { header_width = 92.0 }
    if !finite(cell_width) || !finite(row_height) || !finite(header_width) || header_width < 38.0 || row_height < 20.0 { ret (zero, TooLarge) }
    let lifeline_top = bounds.y + 28.0
    let lifeline_bottom = bounds.y + bounds.height
    let dash = (lifeline_bottom - lifeline_top) / 19.0
    if !finite(dash) || dash <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < participants.len {
        let center = bounds.x + (f32(i) + 0.5) * cell_width
        let x = center - header_width * 0.5
        if !finite(x) || !finite(center) { ret (zero, Invalid) }
        header_boxes[i] = geometry.rect(x, bounds.y, header_width, 24.0)
        var part = 0usize
        while part < 10usize {
            let from_y = lifeline_top + f32(part * 2usize) * dash
            var to_y = from_y + dash
            if to_y > lifeline_bottom { to_y = lifeline_bottom }
            lifeline_segments[i * 10usize + part] = Segment { from: Coord { x: center, y: from_y }, to: Coord { x: center, y: to_y } }
            part += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < activations.len {
        let activation = activations[i]
        if activation.participant >= participants.len || activation.first > activation.last || activation.last >= messages.len { ret (zero, Invalid) }
        let center = bounds.x + (f32(activation.participant) + 0.5) * cell_width
        let top = bounds.y + 38.0 + (f32(activation.first) + 0.5) * row_height - 9.0
        let bottom = bounds.y + 38.0 + (f32(activation.last) + 0.5) * row_height + 9.0
        if !finite(top) || !finite(bottom) || top < lifeline_top || bottom > lifeline_bottom { ret (zero, Invalid) }
        activation_boxes[i] = geometry.rect(center - 4.0, top, 8.0, bottom - top)
        i += 1usize
    }
    var used = 0usize
    i = 0usize
    while i < messages.len {
        let message = messages[i]
        if message.from >= participants.len || message.to >= participants.len { ret (zero, Invalid) }
        let y = bounds.y + 38.0 + (f32(i) + 0.5) * row_height
        let x0 = bounds.x + (f32(message.from) + 0.5) * cell_width
        let x1 = bounds.x + (f32(message.to) + 0.5) * cell_width
        let first = used
        if message.from == message.to {
            if message.kind == .Return || x0 + 26.0 > bounds.x + bounds.width || y - 7.0 < lifeline_top || y + 7.0 > lifeline_bottom { ret (zero, Invalid) }
            let right = x0 + 25.0
            message_segments[used] = Segment { from: Coord { x: x0, y: y - 7.0 }, to: Coord { x: right, y: y - 7.0 } }
            message_segments[used + 1usize] = Segment { from: Coord { x: right, y: y - 7.0 }, to: Coord { x: right, y: y + 7.0 } }
            let tip = Coord { x: x0, y: y + 7.0 }
            message_segments[used + 2usize] = Segment { from: Coord { x: right, y: y + 7.0 }, to: tip }
            message_segments[used + 3usize] = Segment { from: Coord { x: x0 + 6.0, y: tip.y - 4.0 }, to: tip }
            message_segments[used + 4usize] = Segment { from: Coord { x: x0 + 6.0, y: tip.y + 4.0 }, to: tip }
            used += 5usize
            message_labels[i] = Label { text: message.text, anchor: Coord { x: x0 + 27.0, y: y - 9.0 }, align: .Left }
        } else {
            var direction = 1.0f32
            if x1 < x0 { direction = -1.0 }
            let tip = Coord { x: x1, y: y }
            if message.kind == .Return {
                var dash_index = 0usize
                while dash_index < 4usize {
                    let start_fraction = f32(dash_index * 2usize) / 8.0
                    let end_fraction = f32(dash_index * 2usize + 1usize) / 8.0
                    message_segments[used] = Segment { from: Coord { x: x0 + (x1 - x0) * start_fraction, y: y }, to: Coord { x: x0 + (x1 - x0) * end_fraction, y: y } }
                    used += 1usize
                    dash_index += 1usize
                }
            } else {
                message_segments[used] = Segment { from: Coord { x: x0, y: y }, to: tip }
                used += 1usize
            }
            message_segments[used] = Segment { from: Coord { x: x1 - direction * 7.0, y: y - 4.0 }, to: tip }
            message_segments[used + 1usize] = Segment { from: Coord { x: x1 - direction * 7.0, y: y + 4.0 }, to: tip }
            used += 2usize
            message_labels[i] = Label { text: message.text, anchor: Coord { x: (x0 + x1) * 0.5, y: y - 7.0 }, align: .Center }
        }
        message_layers[i] = Layout { kind: .Rug, coords: zero, segments: message_segments[first..used], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
        i += 1usize
    }
    let headers = Layout { kind: .Bar, coords: zero, segments: zero, bars: header_boxes[..participants.len], x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let lifelines = Layout { kind: .Rug, coords: zero, segments: lifeline_segments[..participants.len * 10usize], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let active = Layout { kind: .Bar, coords: zero, segments: zero, bars: activation_boxes[..activations.len], x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (SequenceLayout { headers: headers, lifelines: lifelines, activations: active, messages: message_layers[..messages.len], labels: message_labels[..messages.len] }, ok)
}

fn entity_cardinality(card: EntityCardinality, endpoint: Coord, inward: f32, strokes: []Segment) -> usize {
    var used = 0usize
    if card == .One || card == .ZeroOne {
        let x = endpoint.x + inward * 8.0
        strokes[used] = Segment { from: Coord { x: x, y: endpoint.y - 6.0 }, to: Coord { x: x, y: endpoint.y + 6.0 } }
        used += 1usize
    } else {
        strokes[used] = Segment { from: endpoint, to: Coord { x: endpoint.x + inward * 8.0, y: endpoint.y - 6.0 } }
        strokes[used + 1usize] = Segment { from: endpoint, to: Coord { x: endpoint.x + inward * 8.0, y: endpoint.y + 6.0 } }
        used += 2usize
    }
    if card == .ZeroOne || card == .ZeroMany {
        let center = endpoint.x + inward * 16.0
        var part = 0usize
        while part < 8usize {
            let a = 6.283185307179586f64 * f64(part) / 8.0f64
            let b = 6.283185307179586f64 * f64((part + 1usize) % 8usize) / 8.0f64
            strokes[used] = Segment {
                from: Coord { x: center + 3.0 * f32(math.cos[f64](a)), y: endpoint.y + 3.0 * f32(math.sin[f64](a)) },
                to: Coord { x: center + 3.0 * f32(math.cos[f64](b)), y: endpoint.y + 3.0 * f32(math.sin[f64](b)) },
            }
            used += 1usize
            part += 1usize
        }
    }
    ret used
}

// Explicit table centers and horizontal relationships keep schema ownership
// separate from geometry. Crow's-foot glyphs sit outside table borders.
fn entity_relationship(tables: []const EntityTable, fields: []const EntityField, relations: []const EntityRelation, bounds: geometry.Rect, table_width: f32, table_boxes: []geometry.Rect, header_boxes: []geometry.Rect, field_counts: []usize, field_used: []usize, table_labels: []Label, field_labels: []Label, key_labels: []Label, relation_labels: []Label, relation_segments: []Segment) -> (EntityLayout, err) {
    if tables.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(table_width) || table_width < 68.0 { ret (zero, Invalid) }
    if table_boxes.len < tables.len || header_boxes.len < tables.len || field_counts.len < tables.len || field_used.len < tables.len || table_labels.len < tables.len || field_labels.len < fields.len || key_labels.len < fields.len || relation_labels.len < relations.len || relation_segments.len / 24usize < relations.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < tables.len {
        field_counts[i] = 0usize
        field_used[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < fields.len {
        if fields[i].table >= tables.len { ret (zero, Invalid) }
        field_counts[fields[i].table] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < tables.len {
        let table = tables[i]
        if !finite(table.center.x) || !finite(table.center.y) { ret (zero, Invalid) }
        let height = 24.0 + f32(field_counts[i]) * 18.0
        let x = table.center.x - table_width * 0.5
        let y = table.center.y - height * 0.5
        if !finite(height) || !finite(x) || !finite(y) || x < bounds.x || y < bounds.y || x + table_width > bounds.x + bounds.width || y + height > bounds.y + bounds.height { ret (zero, Invalid) }
        table_boxes[i] = geometry.rect(x, y, table_width, height)
        header_boxes[i] = geometry.rect(x, y, table_width, 24.0)
        var earlier = 0usize
        while earlier < i {
            let other = table_boxes[earlier]
            if x < other.x + other.width && x + table_width > other.x && y < other.y + other.height && y + height > other.y { ret (zero, Invalid) }
            earlier += 1usize
        }
        table_labels[i] = Label { text: table.name, anchor: Coord { x: table.center.x, y: y + 15.0 }, align: .Center }
        i += 1usize
    }
    var keys_used = 0usize
    i = 0usize
    while i < fields.len {
        let field = fields[i]
        let box = table_boxes[field.table]
        let y = box.y + 24.0 + (f32(field_used[field.table]) + 0.5) * 18.0 + 3.0
        let x = box.x + 6.0
        if field.key == .None {
            field_labels[i] = Label { text: field.name, anchor: Coord { x: x, y: y }, align: .Left }
        } else {
            var tag = "FK"
            if field.key == .Primary { tag = "PK" }
            key_labels[keys_used] = Label { text: tag, anchor: Coord { x: x, y: y }, align: .Left }
            keys_used += 1usize
            field_labels[i] = Label { text: field.name, anchor: Coord { x: x + 21.0, y: y }, align: .Left }
        }
        field_used[field.table] += 1usize
        i += 1usize
    }
    var segments_used = 0usize
    i = 0usize
    while i < relations.len {
        let relation = relations[i]
        if relation.from >= tables.len || relation.to >= tables.len || relation.from == relation.to { ret (zero, Invalid) }
        let from = table_boxes[relation.from]
        let to = table_boxes[relation.to]
        var direction = 1.0f32
        if to.x < from.x { direction = -1.0 }
        var x0 = from.x + from.width
        var x1 = to.x
        if direction < 0.0 {
            x0 = from.x
            x1 = to.x + to.width
        }
        let gap = (x1 - x0) * direction
        if !finite(gap) || gap < 40.0 { ret (zero, TooLarge) }
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let mid = x0 + (x1 - x0) * 0.5
        relation_segments[segments_used] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: mid, y: y0 } }
        relation_segments[segments_used + 1usize] = Segment { from: Coord { x: mid, y: y0 }, to: Coord { x: mid, y: y1 } }
        relation_segments[segments_used + 2usize] = Segment { from: Coord { x: mid, y: y1 }, to: Coord { x: x1, y: y1 } }
        segments_used += 3usize
        segments_used += entity_cardinality(relation.from_card, Coord { x: x0, y: y0 }, direction, relation_segments[segments_used..])
        segments_used += entity_cardinality(relation.to_card, Coord { x: x1, y: y1 }, -direction, relation_segments[segments_used..])
        relation_labels[i] = Label { text: relation.name, anchor: Coord { x: mid, y: y0 - 12.0 }, align: .Center }
        i += 1usize
    }
    let table_layer = Layout { kind: .Bar, coords: zero, segments: zero, bars: table_boxes[..tables.len], x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let header_layer = Layout { kind: .Bar, coords: zero, segments: zero, bars: header_boxes[..tables.len], x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    let connector_layer = Layout { kind: .Rug, coords: zero, segments: relation_segments[..segments_used], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (EntityLayout { tables: table_layer, headers: header_layer, connectors: connector_layer, table_labels: table_labels[..tables.len], field_labels: field_labels[..fields.len], key_labels: key_labels[..keys_used], relation_labels: relation_labels[..relations.len] }, ok)
}

// One rooted process DAG. Every split's outgoing fractions sum to one; joins
// add surviving flow. Expected processing time weights each stage by arrivals.
fn branching_process_map(steps: []const BranchStep, routes: []const BranchRoute, bounds: geometry.Rect, work: BranchWork, boxes: []geometry.Rect, arrows: []Segment) -> (BranchLayout, err) {
    let n = steps.len
    if n == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if work.indegree.len < n || work.head.len < n || work.order.len < n || work.stage.len < n || work.stage_counts.len < n || work.stage_used.len < n || work.flow.len < n || work.branch_sum.len < n || work.next.len < routes.len || boxes.len < n || arrows.len / 5usize < routes.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if !finite64(steps[i].process_time) || steps[i].process_time < 0.0f64 || !finite64(steps[i].good_fraction) || steps[i].good_fraction < 0.0f64 || steps[i].good_fraction > 1.0f64 { ret (zero, Invalid) }
        work.indegree[i] = 0usize
        work.head[i] = 0usize
        work.stage[i] = 0usize
        work.stage_counts[i] = 0usize
        work.stage_used[i] = 0usize
        work.flow[i] = 0.0f64
        work.branch_sum[i] = 0.0f64
        i += 1usize
    }
    i = routes.len
    while i > 0usize {
        i -= 1usize
        let route = routes[i]
        if route.from >= n || route.to >= n || route.from == route.to || !finite64(route.fraction) || route.fraction < 0.0f64 || route.fraction > 1.0f64 { ret (zero, Invalid) }
        work.indegree[route.to] += 1usize
        work.branch_sum[route.from] += route.fraction
        if !finite64(work.branch_sum[route.from]) { ret (zero, Invalid) }
        work.next[i] = work.head[route.from]
        work.head[route.from] = i + 1usize
    }
    if work.indegree[0usize] != 0usize { ret (zero, Invalid) }
    i = 1usize
    while i < n {
        if work.indegree[i] == 0usize { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < n {
        if work.head[i] != 0usize && (work.branch_sum[i] < 0.999999f64 || work.branch_sum[i] > 1.000001f64) { ret (zero, Invalid) }
        i += 1usize
    }
    work.flow[0usize] = 1.0f64
    work.order[0usize] = 0usize
    var front = 0usize
    var tail = 1usize
    var stages = 1usize
    var sinks = 0usize
    var output_fraction = 0.0f64
    var expected_processing_time = 0.0f64
    while front < tail {
        let node = work.order[front]
        expected_processing_time += work.flow[node] * steps[node].process_time
        let surviving = work.flow[node] * steps[node].good_fraction
        if !finite64(expected_processing_time) || !finite64(surviving) { ret (zero, Invalid) }
        if work.head[node] == 0usize {
            output_fraction += surviving
            sinks += 1usize
        }
        var edge = work.head[node]
        while edge != 0usize {
            let to = routes[edge - 1usize].to
            let next_stage = work.stage[node] + 1usize
            if next_stage > work.stage[to] { work.stage[to] = next_stage }
            if next_stage + 1usize > stages { stages = next_stage + 1usize }
            work.flow[to] += surviving * routes[edge - 1usize].fraction
            if !finite64(work.flow[to]) { ret (zero, Invalid) }
            work.indegree[to] -= 1usize
            if work.indegree[to] == 0usize {
                work.order[tail] = to
                tail += 1usize
            }
            edge = work.next[edge - 1usize]
        }
        front += 1usize
    }
    if tail != n || !finite64(output_fraction) || output_fraction < 0.0f64 || output_fraction > 1.000001f64 { ret (zero, Invalid) }
    i = 0usize
    while i < n {
        work.stage_counts[work.stage[i]] += 1usize
        i += 1usize
    }
    let cell_width = bounds.width / f32(stages)
    var box_width = cell_width * 0.68
    if box_width > 96.0 { box_width = 96.0 }
    let box_height = 30.0f32
    if !finite(cell_width) || !finite(box_width) || box_width < 32.0 { ret (zero, TooLarge) }
    i = 0usize
    while i < n {
        let rank = work.stage[i]
        let slot_height = bounds.height / f32(work.stage_counts[rank])
        if !finite(slot_height) || slot_height < box_height + 6.0 { ret (zero, TooLarge) }
        let x = bounds.x + (f32(rank) + 0.5) * cell_width - box_width * 0.5
        let y = bounds.y + (f32(work.stage_used[rank]) + 0.5) * slot_height - box_height * 0.5
        if !finite(x) || !finite(y) || !finite(x + box_width) || !finite(y + box_height) { ret (zero, Invalid) }
        boxes[i] = geometry.rect(x, y, box_width, box_height)
        work.stage_used[rank] += 1usize
        i += 1usize
    }
    i = 0usize
    while i < routes.len {
        let from = boxes[routes[i].from]
        let to = boxes[routes[i].to]
        let x0 = from.x + from.width
        let x1 = to.x
        let y0 = from.y + from.height * 0.5
        let y1 = to.y + to.height * 0.5
        let middle = x0 + (x1 - x0) * 0.5
        var head = (x1 - x0) * 0.18
        if head > 7.0 { head = 7.0 }
        if !finite(middle) || !finite(head) || head <= 0.0 { ret (zero, TooLarge) }
        let tip = Coord { x: x1, y: y1 }
        let first = i * 5usize
        arrows[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: middle, y: y0 } }
        arrows[first + 1usize] = Segment { from: Coord { x: middle, y: y0 }, to: Coord { x: middle, y: y1 } }
        arrows[first + 2usize] = Segment { from: Coord { x: middle, y: y1 }, to: tip }
        arrows[first + 3usize] = Segment { from: Coord { x: x1 - head, y: y1 - head * 0.7 }, to: tip }
        arrows[first + 4usize] = Segment { from: Coord { x: x1 - head, y: y1 + head * 0.7 }, to: tip }
        i += 1usize
    }
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: boxes[..n], x_min: 0.0, x_max: f32(stages), y_min: 0.0, y_max: 1.0 }
    let connectors = Layout { kind: .Rug, coords: zero, segments: arrows[..routes.len * 5usize], bars: zero, x_min: 0.0, x_max: f32(stages), y_min: 0.0, y_max: 1.0 }
    let summary = BranchSummary { output_fraction: output_fraction, expected_processing_time: expected_processing_time, stages: stages, sinks: sinks }
    ret (BranchLayout { nodes: nodes, connectors: connectors, summary: summary }, ok)
}

// Ordered half-open spans map to categorical rows. Uncovered time remains blank.
// ponytail: coalescing uses exact shared endpoints; normalize jittery clocks upstream.
fn state_timeline(spans: []const StateSpan, rows: usize, states: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, row_gap: f32, rects: []geometry.Rect, state_ids: []usize, layers: []Layout) -> ([]Layout, err) {
    if spans.len == 0usize || rows == 0usize || states == 0usize { ret (zero, Empty) }
    if !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !valid_bounds(bounds) || !finite(row_gap) || row_gap < 0.0 { ret (zero, Invalid) }
    if rects.len < spans.len || state_ids.len < spans.len || layers.len < spans.len { ret (zero, TooLarge) }
    let total_gap = row_gap * f32(rows - 1usize)
    if !finite(total_gap) || total_gap >= bounds.height { ret (zero, Invalid) }
    let lane_height = (bounds.height - total_gap) / f32(rows)
    if !finite(lane_height) || lane_height <= 0.0 { ret (zero, Invalid) }
    var used = 0usize
    var i = 0usize
    while i < spans.len {
        let span = spans[i]
        if span.row >= rows || span.state >= states || !finite64(span.start) || !finite64(span.end) || span.start < domain_start || span.end > domain_end || span.end <= span.start { ret (zero, Invalid) }
        if i > 0usize {
            let before = spans[i - 1usize]
            if span.row < before.row || (span.row == before.row && span.start < before.end) { ret (zero, Invalid) }
        }
        let left = bounds.x + bounds.width * f32((span.start - domain_start) / (domain_end - domain_start))
        let right = bounds.x + bounds.width * f32((span.end - domain_start) / (domain_end - domain_start))
        let top = bounds.y + f32(span.row) * (lane_height + row_gap)
        if !finite(left) || !finite(right) || !finite(top) || right <= left { ret (zero, Invalid) }
        var merged = false
        if i > 0usize {
            let before = spans[i - 1usize]
            if span.row == before.row && span.state == before.state && span.start == before.end {
                rects[used - 1usize].width = right - rects[used - 1usize].x
                merged = true
            }
        }
        if !merged {
            rects[used] = geometry.rect(left, top, right - left, lane_height)
            state_ids[used] = span.state
            layers[used] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rects[used..used + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: f32(rows) }
            used += 1usize
        }
        i += 1usize
    }
    ret (layers[..used], ok)
}

// Discrete events become lane-centered lollipop marks on an f64 time domain.
fn event_timeline(events: []const TimelineEvent, rows: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, points: []Coord, stems: []Segment) -> (Layout, err) {
    if events.len == 0usize { ret (zero, Empty) }
    if rows == 0usize || !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < events.len || stems.len < events.len { ret (zero, TooLarge) }
    let lane = bounds.height / f32(rows)
    if !finite(lane) || lane <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < events.len {
        let e = events[i]
        if e.row >= rows || !finite64(e.time) || e.time < domain_start || e.time > domain_end || (i > 0usize && e.time < events[i - 1usize].time) { ret (zero, Invalid) }
        let x = bounds.x + bounds.width * f32((e.time - domain_start) / (domain_end - domain_start))
        let y = bounds.y + (f32(e.row) + 0.5) * lane
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        stems[i] = Segment { from: Coord { x: x, y: y + lane * 0.28 }, to: points[i] }
        i += 1usize
    }
    ret (Layout { kind: .Lollipop, coords: points[..events.len], segments: stems[..events.len], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: f32(rows) }, ok)
}

// Milestones reuse event positions but fill diamonds instead of lollipop dots.
fn milestone_roadmap(events: []const TimelineEvent, rows: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, size: f32, centers: []Coord, stems: []Segment, diamonds: []Coord, layers: []Layout) -> ([]Layout, err) {
    let x_min = f32(domain_start)
    let x_max = f32(domain_end)
    if !finite(x_min) || !finite(x_max) || x_max <= x_min || !finite(size) || size <= 0.0 { ret (zero, Invalid) }
    if diamonds.len / 4usize < events.len || layers.len < events.len { ret (zero, TooLarge) }
    let (positions, position_error) = event_timeline(events, rows, domain_start, domain_end, bounds, centers, stems)
    if position_error != ok { ret (zero, position_error) }
    let lane = bounds.height / f32(rows)
    if !finite(lane) || size > lane * 0.5 { ret (zero, Invalid) }
    var i = 0usize
    while i < events.len {
        let center = positions.coords[i]
        if !finite(center.x - size) || !finite(center.x + size) || !finite(center.y - size) || !finite(center.y + size) { ret (zero, Invalid) }
        let start = i * 4usize
        diamonds[start] = Coord { x: center.x, y: center.y - size }
        diamonds[start + 1usize] = Coord { x: center.x + size, y: center.y }
        diamonds[start + 2usize] = Coord { x: center.x, y: center.y + size }
        diamonds[start + 3usize] = Coord { x: center.x - size, y: center.y }
        layers[i] = Layout { kind: .Area, coords: diamonds[start..start + 4usize], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: 0.0, y_max: f32(rows) }
        i += 1usize
    }
    ret (layers[..events.len], ok)
}

fn chord_point(center: Coord, radius: f64, angle: f64) -> Coord {
    ret Coord { x: center.x + f32(radius * math.cos[f64](angle)), y: center.y + f32(radius * math.sin[f64](angle)) }
}

fn chord_curve(from: Coord, to: Coord, center: Coord, t: f32) -> Coord {
    let back = 1.0 - t
    ret Coord { x: back * back * from.x + 2.0 * back * t * center.x + t * t * to.x, y: back * back * from.y + 2.0 * back * t * center.y + t * t * to.y }
}

// Row-major directed weights: each row owns a group arc; opposite cells form
// one possibly tapered ribbon. Ribbons paint before the outer group rings.
// ponytail: fixed-step curves; add adaptive tessellation for zoomed exports.
fn chord(values: []const f32, groups: usize, bounds: geometry.Rect, hole: f32, gap: f32, steps: usize, totals: []f64, arcs: []SunburstArc, subarcs: []SunburstArc, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if groups == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(hole) || hole <= 0.0 || hole >= 1.0 || !finite(gap) || gap < 0.0 || steps < 2usize || values.len / groups != groups || values.len % groups != 0usize { ret (zero, Invalid) }
    let pairs = groups * (groups + 1usize) / 2usize
    if totals.len < groups || arcs.len < groups || subarcs.len < values.len || layers.len < pairs + groups || points.len < 2usize || steps > (points.len - 2usize) / 4usize { ret (zero, TooLarge) }
    let turn = 6.283185307179586f64
    let available = turn - f64(gap) * f64(groups)
    if available <= 0.0f64 { ret (zero, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < groups {
        var row = 0.0f64
        var j = 0usize
        while j < groups {
            let value = values[i * groups + j]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            row += f64(value)
            j += 1usize
        }
        if !finite(f32(row)) { ret (zero, Invalid) }
        totals[i] = row
        total += row
        i += 1usize
    }
    if !finite(f32(total)) || total <= 0.0f64 { ret (zero, Invalid) }
    var radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { radius = f64(bounds.height) * 0.5f64 }
    let inner = radius * f64(hole)
    let center = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * 0.5f64), y: f32(f64(bounds.y) + f64(bounds.height) * 0.5f64) }
    if !finite(center.x) || !finite(center.y) || !finite(f32(radius)) || !finite(f32(inner)) || inner <= 0.0f64 || inner >= radius { ret (zero, Invalid) }
    var angle = -1.5707963267948966f64 + f64(gap) * 0.5f64
    i = 0usize
    while i < groups {
        let end = angle + available * totals[i] / total
        arcs[i] = SunburstArc { start: angle, end: end, next: angle }
        var cursor = angle
        var j = 0usize
        while j < groups {
            var subend = cursor
            if totals[i] > 0.0f64 { subend += (end - angle) * f64(values[i * groups + j]) / totals[i] }
            subarcs[i * groups + j] = SunburstArc { start: cursor, end: subend, next: cursor }
            cursor = subend
            j += 1usize
        }
        angle = end + f64(gap)
        i += 1usize
    }
    var needed = 0usize
    i = 0usize
    while i < groups {
        var j = i
        while j < groups {
            if values[i * groups + j] > 0.0 || values[j * groups + i] > 0.0 {
                var count = 4usize * steps + 2usize
                if i == j { count = 2usize * steps + 1usize }
                if count > points.len - needed { ret (zero, TooLarge) }
                needed += count
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < groups {
        if totals[i] > 0.0f64 {
            let count = 2usize * (steps + 1usize)
            if count > points.len - needed { ret (zero, TooLarge) }
            needed += count
        }
        i += 1usize
    }
    var used = 0usize
    var layer = 0usize
    i = 0usize
    while i < groups {
        var j = i
        while j < groups {
            if values[i * groups + j] == 0.0 && values[j * groups + i] == 0.0 {
                layers[layer] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            } else {
                let source = subarcs[i * groups + j]
                let destination = subarcs[j * groups + i]
                let first = used
                var k = 0usize
                while k <= steps {
                    let a = source.start + (source.end - source.start) * f64(k) / f64(steps)
                    points[used] = chord_point(center, inner, a)
                    used += 1usize
                    k += 1usize
                }
                let source_end = points[used - 1usize]
                let source_start = points[first]
                var target_start = source_start
                if i != j { target_start = chord_point(center, inner, destination.start) }
                k = 1usize
                while k <= steps {
                    points[used] = chord_curve(source_end, target_start, center, f32(k) / f32(steps))
                    used += 1usize
                    k += 1usize
                }
                if i != j {
                    k = 0usize
                    while k <= steps {
                        let a = destination.start + (destination.end - destination.start) * f64(k) / f64(steps)
                        points[used] = chord_point(center, inner, a)
                        used += 1usize
                        k += 1usize
                    }
                    let target_end = points[used - 1usize]
                    k = 1usize
                    while k <= steps {
                        points[used] = chord_curve(target_end, source_start, center, f32(k) / f32(steps))
                        used += 1usize
                        k += 1usize
                    }
                }
                layers[layer] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            }
            layer += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < groups {
        if totals[i] == 0.0f64 {
            layers[layer] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let first = used
            var k = 0usize
            while k <= steps {
                let a = arcs[i].start + (arcs[i].end - arcs[i].start) * f64(k) / f64(steps)
                points[used] = chord_point(center, radius, a)
                used += 1usize
                k += 1usize
            }
            k = 0usize
            while k <= steps {
                let a = arcs[i].end - (arcs[i].end - arcs[i].start) * f64(k) / f64(steps)
                points[used] = chord_point(center, inner, a)
                used += 1usize
                k += 1usize
            }
            layers[layer] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        layer += 1usize
        i += 1usize
    }
    i = 0usize
    while i < used {
        if !finite(points[i].x) || !finite(points[i].y) { ret (zero, Invalid) }
        i += 1usize
    }
    ret (layers[..layer], ok)
}

// Ordered categories occupy a fixed grid, rounded at cumulative boundaries.
fn waffle(values: []const f32, bounds: geometry.Rect, columns: usize, rows: usize, gap: f32, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || columns == 0usize || rows == 0usize || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if columns > bars.len / rows || layers.len < values.len { ret (zero, TooLarge) }
    let count = columns * rows
    let width = bounds.width / f32(columns)
    let height = bounds.height / f32(rows)
    if !finite(width) || !finite(height) || gap >= width || gap >= height { ret (zero, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    var cumulative = 0.0f64
    var used = 0usize
    i = 0usize
    while i < values.len {
        cumulative += f64(values[i])
        var end_cell = count
        if i + 1usize < values.len {
            // ponytail: ordered cumulative rounding can bias a category by one cell;
            // use caller-scratch largest remainders if per-category fairness matters.
            end_cell = usize(cumulative / total * f64(count) + 0.5f64)
            if end_cell > count { end_cell = count }
        }
        let first = used
        while used < end_cell {
            let column = used % columns
            let row = used / columns
            bars[used] = geometry.rect(bounds.x + width * f32(column) + gap * 0.5,
                bounds.y + bounds.height - height * f32(row + 1usize) + gap * 0.5,
                width - gap, height - gap)
            used += 1usize
        }
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[first..used], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

// Parent indices precede children; root 0 names itself and only leaves carry
// weights. Reused by rectangular and radial hierarchy layouts.
fn hierarchy_totals(parents: []const usize, weights: []const f32, totals: []f64) -> err {
    if parents.len == 0usize { ret Empty }
    if parents.len != weights.len || parents[0usize] != 0usize { ret Invalid }
    if totals.len < parents.len { ret TooLarge }
    var i = 0usize
    while i < parents.len {
        if (i > 0usize && parents[i] >= i) || !finite(weights[i]) || weights[i] < 0.0 { ret Invalid }
        if i > 0usize && weights[parents[i]] != 0.0 { ret Invalid }
        totals[i] = f64(weights[i])
        i += 1usize
    }
    i = parents.len
    while i > 1usize {
        i -= 1usize
        totals[parents[i]] += totals[i]
        if !finite64(totals[parents[i]]) { ret Invalid }
    }
    if !(totals[0usize] > 0.0f64) { ret Invalid }
    ret ok
}

// A static measure decomposition. Nodes are in depth-first preorder, root 0
// names itself, and only leaves carry nonnegative measure values. Each card's
// bar shows its fraction of its parent's rolled-up total (root: full bar).
fn aggregate_decomposition_tree(parents: []const usize, weights: []const f32, bounds: geometry.Rect, totals: []f64, depths: []usize, spans: []geometry.Rect, cards: []geometry.Rect, value_bars: []geometry.Rect, connectors: []Segment) -> (AggregateTreeLayout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    let n = parents.len
    if depths.len < n || spans.len < n || cards.len < n || value_bars.len < n || connectors.len / 3usize < n - 1usize { ret (zero, TooLarge) }
    depths[0usize] = 0usize
    var levels = 1usize
    var leaves = 0usize
    var i = 0usize
    while i < n {
        if i > 0usize {
            // A depth-first preorder keeps every subtree's leaf interval
            // contiguous, so the caller can label parents at its midpoint.
            var ancestor = i - 1usize
            while ancestor > parents[i] { ancestor = parents[ancestor] }
            if ancestor != parents[i] { ret (zero, Invalid) }
            depths[i] = depths[parents[i]] + 1usize
            if depths[i] + 1usize > levels { levels = depths[i] + 1usize }
        }
        spans[i] = geometry.rect(0.0, 0.0, 0.0, 0.0)
        var child = false
        var j = i + 1usize
        while j < n {
            if parents[j] == i { child = true }
            j += 1usize
        }
        if !child {
            spans[i] = geometry.rect(0.0, f32(leaves), 0.0, 1.0)
            leaves += 1usize
        }
        i += 1usize
    }
    i = n
    while i > 1usize {
        i -= 1usize
        let p = parents[i]
        if spans[p].height == 0.0 {
            spans[p] = spans[i]
        } else {
            let top = spans[p].y
            var low = spans[i].y
            if top < low { low = top }
            var high = spans[p].y + spans[p].height
            let child_high = spans[i].y + spans[i].height
            if child_high > high { high = child_high }
            spans[p] = geometry.rect(0.0, low, 0.0, high - low)
        }
    }
    let column = bounds.width / f32(levels)
    let row = bounds.height / f32(leaves)
    var card_width = column * 0.72
    if card_width > 116.0 { card_width = 116.0 }
    var card_height = row * 0.65
    if card_height > 38.0 { card_height = 38.0 }
    if !finite(column) || !finite(row) || column < 56.0 || row < 20.0 || !finite(card_width) || !finite(card_height) { ret (zero, TooLarge) }
    i = 0usize
    while i < n {
        let x = bounds.x + f32(depths[i]) * column + (column - card_width) * 0.5
        let y = bounds.y + (spans[i].y + spans[i].height * 0.5) * row - card_height * 0.5
        if !finite(x + card_width) || !finite(y + card_height) { ret (zero, Invalid) }
        cards[i] = geometry.rect(x, y, card_width, card_height)
        var ratio = 1.0f64
        if i > 0usize { ratio = totals[i] / totals[parents[i]] }
        if !finite64(ratio) || ratio < 0.0f64 || ratio > 1.0f64 { ret (zero, Invalid) }
        value_bars[i] = geometry.rect(x + 4.0, y + card_height - 6.0, (card_width - 8.0) * f32(ratio), 3.0)
        if i > 0usize {
            let parent_card = cards[parents[i]]
            let x0 = parent_card.x + parent_card.width
            let x1 = x
            let y0 = parent_card.y + parent_card.height * 0.5
            let y1 = y + card_height * 0.5
            let middle = (x0 + x1) * 0.5
            let first = (i - 1usize) * 3usize
            connectors[first] = Segment { from: Coord { x: x0, y: y0 }, to: Coord { x: middle, y: y0 } }
            connectors[first + 1usize] = Segment { from: Coord { x: middle, y: y0 }, to: Coord { x: middle, y: y1 } }
            connectors[first + 2usize] = Segment { from: Coord { x: middle, y: y1 }, to: Coord { x: x1, y: y1 } }
        }
        i += 1usize
    }
    let nodes = Layout { kind: .Bar, coords: zero, segments: zero, bars: cards[..n], x_min: 0.0, x_max: f32(levels), y_min: 0.0, y_max: f32(leaves) }
    let bars = Layout { kind: .Bar, coords: zero, segments: zero, bars: value_bars[..n], x_min: 0.0, x_max: f32(levels), y_min: 0.0, y_max: f32(leaves) }
    let lines = Layout { kind: .Rug, coords: zero, segments: connectors[..(n - 1usize) * 3usize], bars: zero, x_min: 0.0, x_max: f32(levels), y_min: 0.0, y_max: f32(leaves) }
    ret (AggregateTreeLayout { nodes: nodes, value_bars: bars, connectors: lines, levels: levels, leaves: leaves }, ok)
}

// Every node gets a rectangle, while only leaves get a Bar layer.
fn treemap(parents: []const usize, weights: []const f32, bounds: geometry.Rect, totals: []f64, rects: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if rects.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    rects[0usize] = bounds
    var i = 0usize
    while i < parents.len {
        var children = 0usize
        var j = 1usize
        while j < parents.len {
            if parents[j] == i { children += 1usize }
            j += 1usize
        }
        if children > 0usize {
            let parent = rects[i]
            let across = parent.width >= parent.height
            var cumulative = 0.0f64
            var placed = 0usize
            // ponytail: sibling scans are O(n^2) and long strips are possible;
            // use caller-scratch squarification if very large trees need it.
            j = 1usize
            while j < parents.len {
                if parents[j] == i {
                    placed += 1usize
                    var start = 0.0f64
                    var finish = 0.0f64
                    if totals[i] > 0.0f64 {
                        start = cumulative / totals[i]
                        cumulative += totals[j]
                        finish = cumulative / totals[i]
                    }
                    if placed == children { finish = 1.0f64 }
                    if across {
                        let left = parent.x + parent.width * f32(start)
                        let right = parent.x + parent.width * f32(finish)
                        if !finite(left) || !finite(right) || right < left { ret (zero, Invalid) }
                        rects[j] = geometry.rect(left, parent.y, right - left, parent.height)
                    } else {
                        let top = parent.y + parent.height * f32(start)
                        let bottom = parent.y + parent.height * f32(finish)
                        if !finite(top) || !finite(bottom) || bottom < top { ret (zero, Invalid) }
                        rects[j] = geometry.rect(parent.x, top, parent.width, bottom - top)
                    }
                }
                j += 1usize
            }
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rects[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Depth occupies horizontal bands; each sibling keeps its subtree's width.
// Shallow leaves extend to the bottom of the panel.
fn icicle(parents: []const usize, weights: []const f32, bounds: geometry.Rect, totals: []f64, depths: []usize, rects: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if depths.len < parents.len || rects.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    depths[0usize] = 0usize
    var max_depth = 0usize
    var i = 1usize
    while i < parents.len {
        depths[i] = depths[parents[i]] + 1usize
        if depths[i] > max_depth { max_depth = depths[i] }
        i += 1usize
    }
    let row_height = bounds.height / f32(max_depth + 1usize)
    if !finite(row_height) || row_height <= 0.0 { ret (zero, Invalid) }
    rects[0usize] = geometry.rect(bounds.x, bounds.y, bounds.width, row_height)
    i = 1usize
    while i < parents.len {
        let parent = parents[i]
        var before = 0.0f64
        var j = 1usize
        // ponytail: preceding-sibling scans are O(n^2); use caller-owned
        // per-parent cursors only if large hierarchies need linear layout.
        while j < i {
            if parents[j] == parent { before += totals[j] }
            j += 1usize
        }
        var left = rects[parent].x
        var right = left
        if totals[parent] > 0.0f64 {
            left += rects[parent].width * f32(before / totals[parent])
            right = rects[parent].x + rects[parent].width * f32((before + totals[i]) / totals[parent])
        }
        let top = bounds.y + f32(depths[i]) * row_height
        var bottom = top + row_height
        if weights[i] > 0.0 { bottom = bounds.y + bounds.height }
        if !finite(left) || !finite(right) || !finite(top) || !finite(bottom) || right < left || bottom < top { ret (zero, Invalid) }
        rects[i] = geometry.rect(left, top, right - left, bottom - top)
        i += 1usize
    }
    if weights[0usize] > 0.0 { rects[0usize] = bounds }
    i = 0usize
    while i < parents.len {
        var bars: []geometry.Rect = zero
        if totals[i] > 0.0f64 { bars = rects[i..i + 1usize] }
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Siblings occupy disjoint circles inside their parent; area ratios match
// subtree totals. Each sibling group uses one deterministic ring.
fn circle_pack(parents: []const usize, weights: []const f32, bounds: geometry.Rect, padding: f32, totals: []f64, circles: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(padding) || padding < 0.0 || padding >= 1.0 { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if circles.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    var root_radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { root_radius = f64(bounds.height) * 0.5f64 }
    let root_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let root_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    if !finite(f32(root_x - root_radius)) || !finite(f32(root_y - root_radius)) || !finite(f32(root_radius * 2.0f64)) { ret (zero, Invalid) }
    circles[0usize] = geometry.rect(f32(root_x - root_radius), f32(root_y - root_radius), f32(root_radius * 2.0f64), f32(root_radius * 2.0f64))
    var i = 0usize
    while i < parents.len {
        var count = 0usize
        var maximum = 0.0f64
        var j = i + 1usize
        while j < parents.len {
            if parents[j] == i {
                count += 1usize
                if totals[j] > maximum { maximum = totals[j] }
            }
            j += 1usize
        }
        if count > 0usize {
            let parent = circles[i]
            let center_x = f64(parent.x) + f64(parent.width) * 0.5f64
            let center_y = f64(parent.y) + f64(parent.height) * 0.5f64
            let parent_radius = f64(parent.width) * 0.5f64
            let ring = parent_radius * f64(1.0 - padding) * 0.5f64
            var rank = 0usize
            // ponytail: sibling scans are O(n^2) and ring packing wastes space
            // for large groups; use caller-scratch tangent packing if density matters.
            j = i + 1usize
            while j < parents.len {
                if parents[j] == i {
                    var angle = 0.0f64
                    var radius = 0.0f64
                    if count == 1usize {
                        radius = parent_radius * f64(1.0 - padding)
                    } else {
                        angle = 6.283185307179586f64 * f64(rank) / f64(count)
                        if maximum > 0.0f64 { radius = ring * math.sin[f64](3.141592653589793f64 / f64(count)) * math.sqrt[f64](totals[j] / maximum) }
                    }
                    var x = center_x
                    var y = center_y
                    if count > 1usize {
                        x += ring * math.cos[f64](angle)
                        y += ring * math.sin[f64](angle)
                    }
                    let left = f32(x - radius)
                    let top = f32(y - radius)
                    let diameter = f32(radius * 2.0f64)
                    if !finite(left) || !finite(top) || !finite(diameter) || (totals[j] > 0.0f64 && diameter <= 0.0) { ret (zero, Invalid) }
                    circles[j] = geometry.rect(left, top, diameter, diameter)
                    rank += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < parents.len {
        var bars: []geometry.Rect = zero
        if totals[i] > 0.0f64 { bars = circles[i..i + 1usize] }
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Exact two-circle overlap in the same area units as r1 and r2.
fn circle_overlap_area(r1: f64, r2: f64, distance: f64) -> f64 {
    let pi = 3.141592653589793f64
    if distance >= r1 + r2 { ret 0.0f64 }
    var difference = r1 - r2
    if difference < 0.0f64 { difference = 0.0f64 - difference }
    if distance <= difference {
        var smaller = r1
        if r2 < smaller { smaller = r2 }
        ret pi * smaller * smaller
    }
    var first = (distance * distance + r1 * r1 - r2 * r2) / (2.0f64 * distance * r1)
    var second = (distance * distance + r2 * r2 - r1 * r1) / (2.0f64 * distance * r2)
    if first < -1.0f64 { first = -1.0f64 }
    if first > 1.0f64 { first = 1.0f64 }
    if second < -1.0f64 { second = -1.0f64 }
    if second > 1.0f64 { second = 1.0f64 }
    var root = (0.0f64 - distance + r1 + r2) * (distance + r1 - r2) * (distance - r1 + r2) * (distance + r1 + r2)
    if root < 0.0f64 { root = 0.0f64 }
    ret r1 * r1 * math.acos[f64](first) + r2 * r2 * math.acos[f64](second) - 0.5f64 * math.sqrt[f64](root)
}

// Two-set area-proportional Euler diagram. A full subset is concentric;
// disjoint sets get a small visual gap. The caller owns both circle marks.
fn euler2(first: f32, second: f32, overlap: f32, bounds: geometry.Rect, circles: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(first) || !finite(second) || !finite(overlap) || first < 0.0 || second < 0.0 || overlap < 0.0 || overlap > first || overlap > second { ret (zero, Invalid) }
    if circles.len < 2usize || layers.len < 2usize { ret (zero, TooLarge) }
    if first == 0.0 && second == 0.0 { ret (zero, Empty) }
    let pi = 3.141592653589793f64
    let r1 = math.sqrt[f64](f64(first) / pi)
    let r2 = math.sqrt[f64](f64(second) / pi)
    var distance = 0.0f64
    if overlap == 0.0 {
        var smaller = r1
        if r2 < smaller { smaller = r2 }
        distance = r1 + r2 + smaller * 0.18f64
    } else {
        var smaller = first
        if second < smaller { smaller = second }
        if overlap < smaller {
            var low = r1 - r2
            if low < 0.0f64 { low = 0.0f64 - low }
            var high = r1 + r2
            var step = 0usize
            while step < 56usize {
                let middle = (low + high) * 0.5f64
                if circle_overlap_area(r1, r2, middle) > f64(overlap) { low = middle } else { high = middle }
                step += 1usize
            }
            distance = (low + high) * 0.5f64
        }
    }
    var left = 0.0f64 - r1
    if distance - r2 < left { left = distance - r2 }
    var right = r1
    if distance + r2 > right { right = distance + r2 }
    var tall = r1
    if r2 > tall { tall = r2 }
    var scale = f64(bounds.width) / (right - left)
    let vertical = f64(bounds.height) / (2.0f64 * tall)
    if vertical < scale { scale = vertical }
    scale *= 0.92f64
    let cx1 = f64(bounds.x) + (f64(bounds.width) - (right - left) * scale) * 0.5f64 - left * scale
    let cx2 = cx1 + distance * scale
    let cy = f64(bounds.y) + f64(bounds.height) * 0.5f64
    let radii = [2]f64{ r1 * scale, r2 * scale }
    let centers = [2]f64{ cx1, cx2 }
    var i = 0usize
    while i < 2usize {
        let x = f32(centers[i] - radii[i])
        let y = f32(cy - radii[i])
        let diameter = f32(2.0f64 * radii[i])
        if !finite(x) || !finite(y) || !finite(diameter) || (radii[i] > 0.0f64 && diameter <= 0.0) { ret (zero, Invalid) }
        circles[i] = geometry.rect(x, y, diameter, diameter)
        var bars: []geometry.Rect = zero
        if diameter > 0.0 { bars = circles[i..i + 1usize] }
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..2usize], ok)
}

// Nominal three-set Venn: all seven memberships have nonempty regions.
// Anchor order is A, B, C, AB, AC, BC, ABC; no area claims are made.
// ponytail: fixed circles cannot encode seven arbitrary region areas; add a fitted-region solver only when those areas are required.
fn venn3(bounds: geometry.Rect, circles: []geometry.Rect, anchors: []Coord, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if circles.len < 3usize || anchors.len < 7usize || layers.len < 3usize { ret (zero, TooLarge) }
    var radius = f64(bounds.width) / 3.15f64
    let vertical = f64(bounds.height) / 2.995929214352104f64
    if vertical < radius { radius = vertical }
    radius *= 0.92f64
    let distance = radius * 1.15f64
    let dy = distance * 0.2886751345948129f64
    let cx = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let cy = f64(bounds.y) + f64(bounds.height) * 0.5f64
    let xs = [3]f64{ cx, cx - distance * 0.5f64, cx + distance * 0.5f64 }
    let ys = [3]f64{ cy - 2.0f64 * dy, cy + dy, cy + dy }
    var i = 0usize
    while i < 3usize {
        let x = f32(xs[i] - radius)
        let y = f32(ys[i] - radius)
        let diameter = f32(2.0f64 * radius)
        if !finite(x) || !finite(y) || !finite(diameter) || diameter <= 0.0 { ret (zero, Invalid) }
        circles[i] = geometry.rect(x, y, diameter, diameter)
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: circles[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    anchors[0usize] = Coord { x: f32(xs[0usize]), y: f32(ys[0usize] - radius * 0.5f64) }
    anchors[1usize] = Coord { x: f32(xs[1usize] - radius * 0.45f64), y: f32(ys[1usize] + radius * 0.3f64) }
    anchors[2usize] = Coord { x: f32(xs[2usize] + radius * 0.45f64), y: f32(ys[2usize] + radius * 0.3f64) }
    anchors[3usize] = Coord { x: f32((xs[0usize] + xs[1usize]) * 0.5f64 - radius * 0.18f64), y: f32((ys[0usize] + ys[1usize]) * 0.5f64) }
    anchors[4usize] = Coord { x: f32((xs[0usize] + xs[2usize]) * 0.5f64 + radius * 0.18f64), y: f32((ys[0usize] + ys[2usize]) * 0.5f64) }
    anchors[5usize] = Coord { x: f32(cx), y: f32(cy + dy + radius * 0.23f64) }
    anchors[6usize] = Coord { x: f32(cx), y: f32(cy) }
    i = 0usize
    while i < 7usize {
        if !finite(anchors[i].x) || !finite(anchors[i].y) { ret (zero, Invalid) }
        i += 1usize
    }
    ret (layers[..3usize], ok)
}

// Nodes are ordered within zero-based columns; links go strictly forward.
// Link layers precede node layers so painted nodes cover ribbon endpoints.
// ponytail: fixed input order can cross ribbons; add barycentric ordering only
// when the caller can supply identity-preserving reorder scratch.
fn sankey(node_columns: []const usize, columns: usize, sources: []const usize, targets: []const usize, values: []const f32, bounds: geometry.Rect, node_width: f32, node_gap: f32, steps: usize, nodes: []SankeyNode, rects: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if node_columns.len == 0usize || sources.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || sources.len != targets.len || sources.len != values.len || !valid_bounds(bounds) || !finite(node_width) || !finite(node_gap) || node_width <= 0.0 || node_gap < 0.0 || steps < 2usize || steps > 64usize { ret (zero, Invalid) }
    if node_columns.len > nodes.len || node_columns.len > rects.len || sources.len > layers.len || node_columns.len > layers.len - sources.len || sources.len > points.len / (2usize * (steps + 1usize)) { ret (zero, TooLarge) }
    let column_width = (bounds.width - node_width) / f32(columns - 1usize)
    if !finite(column_width) || column_width <= node_width { ret (zero, Invalid) }
    var i = 0usize
    while i < node_columns.len {
        if node_columns[i] >= columns { ret (zero, Invalid) }
        nodes[i] = SankeyNode { incoming: 0.0f64, outgoing: 0.0f64, in_used: 0.0f64, out_used: 0.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        if from >= node_columns.len || to >= node_columns.len || node_columns[from] >= node_columns[to] || !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        nodes[from].outgoing += f64(values[i])
        nodes[to].incoming += f64(values[i])
        if !finite64(nodes[from].outgoing) || !finite64(nodes[to].incoming) { ret (zero, Invalid) }
        i += 1usize
    }
    var scale = 0.0f64
    var column = 0usize
    while column < columns {
        var count = 0usize
        var total = 0.0f64
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                count += 1usize
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                total += flow
            }
            i += 1usize
        }
        if count == 0usize || !finite64(total) || total <= 0.0f64 { ret (zero, Invalid) }
        let available = f64(bounds.height) - f64(node_gap) * f64(count - 1usize)
        if !finite64(available) || available <= 0.0f64 { ret (zero, Invalid) }
        let candidate = available / total
        if !finite64(candidate) || candidate <= 0.0f64 { ret (zero, Invalid) }
        if column == 0usize || candidate < scale { scale = candidate }
        column += 1usize
    }
    column = 0usize
    while column < columns {
        var count = 0usize
        var total = 0.0f64
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                count += 1usize
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                total += flow
            }
            i += 1usize
        }
        let used = total * scale + f64(node_gap) * f64(count - 1usize)
        var cursor = f64(bounds.y) + (f64(bounds.height) - used) * 0.5f64
        let x = bounds.x + column_width * f32(column)
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                let height = f32(flow * scale)
                if !finite(x) || !finite(f32(cursor)) || !finite(height) || (flow > 0.0f64 && height <= 0.0) { ret (zero, Invalid) }
                rects[i] = geometry.rect(x, f32(cursor), node_width, height)
                cursor += f64(height) + f64(node_gap)
            }
            i += 1usize
        }
        column += 1usize
    }
    var used_points = 0usize
    i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        let value = f64(values[i])
        if value == 0.0f64 {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let x0 = rects[from].x + node_width
            let x1 = rects[to].x
            let top0 = rects[from].y + f32(nodes[from].out_used * scale)
            let top1 = rects[to].y + f32(nodes[to].in_used * scale)
            let thickness = f32(value * scale)
            if !finite(x0) || !finite(x1) || !finite(top0) || !finite(top1) || !finite(thickness) || thickness <= 0.0 { ret (zero, Invalid) }
            let first = used_points
            var j = 0usize
            while j <= steps {
                let t = f32(j) / f32(steps)
                let eased = t * t * (3.0 - 2.0 * t)
                points[used_points] = Coord { x: x0 + (x1 - x0) * t, y: top0 + (top1 - top0) * eased }
                used_points += 1usize
                j += 1usize
            }
            j = 0usize
            while j <= steps {
                let t = 1.0 - f32(j) / f32(steps)
                let eased = t * t * (3.0 - 2.0 * t)
                points[used_points] = Coord { x: x0 + (x1 - x0) * t, y: top0 + thickness + (top1 - top0) * eased }
                used_points += 1usize
                j += 1usize
            }
            layers[i] = Layout { kind: .Area, coords: points[first..used_points], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        nodes[from].out_used += value
        nodes[to].in_used += value
        i += 1usize
    }
    i = 0usize
    while i < node_columns.len {
        var bars: []geometry.Rect = zero
        if rects[i].height > 0.0 { bars = rects[i..i + 1usize] }
        layers[sources.len + i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..sources.len + node_columns.len], ok)
}

// An alluvial diagram conserves each interior stratum across adjacent stages.
// Each input link remains a separate caller-colourable ribbon.
// ponytail: keep caller order; add crossing reduction only when real charts need it.
fn alluvial(node_columns: []const usize, columns: usize, sources: []const usize, targets: []const usize, values: []const f32, bounds: geometry.Rect, node_width: f32, node_gap: f32, steps: usize, nodes: []SankeyNode, rects: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if node_columns.len == 0usize || sources.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || sources.len != targets.len || sources.len != values.len { ret (zero, Invalid) }
    var i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        if from >= node_columns.len || to >= node_columns.len || node_columns[from] >= columns || node_columns[to] >= columns || node_columns[from] + 1usize != node_columns[to] { ret (zero, Invalid) }
        i += 1usize
    }
    let (marks, layout_error) = sankey(node_columns, columns, sources, targets, values, bounds, node_width, node_gap, steps, nodes, rects, points, layers)
    if layout_error != ok { ret (zero, layout_error) }
    i = 0usize
    while i < node_columns.len {
        if node_columns[i] > 0usize && node_columns[i] + 1usize < columns {
            var difference = nodes[i].incoming - nodes[i].outgoing
            if difference < 0.0f64 { difference = 0.0f64 - difference }
            var size = nodes[i].incoming
            if nodes[i].outgoing > size { size = nodes[i].outgoing }
            if difference > size * 0.000001f64 { ret (zero, Invalid) }
        }
        i += 1usize
    }
    ret (marks, ok)
}

// Root occupies the innermost ring, each generation the next. A leaf extends
// through any remaining rings; zero-total nodes return empty Bar layers.
fn sunburst(parents: []const usize, weights: []const f32, bounds: geometry.Rect, hole: f32, totals: []f64, depths: []usize, arcs: []SunburstArc, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if depths.len < parents.len || arcs.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    let turn = 6.283185307179586f64
    let top = -1.5707963267948966f64
    depths[0usize] = 0usize
    arcs[0usize] = SunburstArc { start: top, end: top + turn, next: top }
    var max_depth = 0usize
    var i = 1usize
    while i < parents.len {
        let parent = parents[i]
        depths[i] = depths[parent] + 1usize
        if depths[i] > max_depth { max_depth = depths[i] }
        let start = arcs[parent].next
        var end = start
        if totals[parent] > 0.0f64 { end += (arcs[parent].end - arcs[parent].start) * totals[i] / totals[parent] }
        if !finite64(end) { ret (zero, Invalid) }
        arcs[parent].next = end
        arcs[i] = SunburstArc { start: start, end: end, next: start }
        i += 1usize
    }
    var radius = bounds.width * 0.5
    if bounds.height < bounds.width { radius = bounds.height * 0.5 }
    let inner = radius * hole
    let ring_width = (radius - inner) / f32(max_depth + 1usize)
    let cx = bounds.x + bounds.width * 0.5
    let cy = bounds.y + bounds.height * 0.5
    if !finite(radius) || !finite(inner) || !finite(ring_width) || ring_width <= 0.0 || !finite(cx) || !finite(cy) { ret (zero, Invalid) }
    var needed = 0usize
    i = 0usize
    while i < parents.len {
        if totals[i] > 0.0f64 {
            let steps = 2usize + usize((arcs[i].end - arcs[i].start) / turn * 96.0f64)
            let count = 2usize * (steps + 1usize)
            if needed > points.len || count > points.len - needed { ret (zero, TooLarge) }
            needed += count
        }
        i += 1usize
    }
    var used = 0usize
    i = 0usize
    while i < parents.len {
        if totals[i] == 0.0f64 {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let fraction_of_turn = (arcs[i].end - arcs[i].start) / turn
            let steps = 2usize + usize(fraction_of_turn * 96.0f64)
            let low = inner + f32(depths[i]) * ring_width
            var high = low + ring_width
            if weights[i] > 0.0 { high = radius }
            let first = used
            var j = 0usize
            while j <= steps {
                let angle = arcs[i].start + (arcs[i].end - arcs[i].start) * f64(j) / f64(steps)
                let x = cx + high * f32(math.cos[f64](angle))
                let y = cy + high * f32(math.sin[f64](angle))
                if !finite(x) || !finite(y) { ret (zero, Invalid) }
                points[used] = Coord { x: x, y: y }
                used += 1usize
                j += 1usize
            }
            j = 0usize
            while j <= steps {
                let angle = arcs[i].end - (arcs[i].end - arcs[i].start) * f64(j) / f64(steps)
                let x = cx + low * f32(math.cos[f64](angle))
                let y = cy + low * f32(math.sin[f64](angle))
                if !finite(x) || !finite(y) { ret (zero, Invalid) }
                points[used] = Coord { x: x, y: y }
                used += 1usize
                j += 1usize
            }
            layers[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// A stage funnel tapers each segment to the next nonincreasing value.
fn funnel(values: []const f32, bounds: geometry.Rect, gap: f32, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if values.len > points.len / 4usize || layers.len < values.len { ret (zero, TooLarge) }
    if !finite(values[0usize]) || values[0usize] <= 0.0 { ret (zero, Invalid) }
    let slot = bounds.height / f32(values.len)
    if !finite(slot) || gap >= slot { ret (zero, Invalid) }
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 || (i > 0usize && values[i] > values[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        var lower = values[i]
        if i + 1usize < values.len { lower = values[i + 1usize] }
        let top_width = bounds.width * (values[i] / values[0usize])
        let bottom_width = bounds.width * (lower / values[0usize])
        let center = bounds.x + bounds.width * 0.5
        let top = bounds.y + slot * f32(i)
        let bottom = top + slot - gap
        let first = 4usize * i
        points[first] = Coord { x: center - top_width * 0.5, y: top }
        points[first + 1usize] = Coord { x: center + top_width * 0.5, y: top }
        points[first + 2usize] = Coord { x: center + bottom_width * 0.5, y: bottom }
        points[first + 3usize] = Coord { x: center - bottom_width * 0.5, y: bottom }
        layers[i] = Layout { kind: .Area, coords: points[first..first + 4usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

// Numeric x positions may be irregular; the smallest interval controls mark
// width while half an interval pads the first and last marks into the panel.
fn ohlc_domain(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32) -> (f32, f32, f32, f32, f32, err) {
    if x.len == 0usize { ret (0.0, 0.0, 0.0, 0.0, 0.0, Empty) }
    if opens.len != x.len || highs.len != x.len || lows.len != x.len || closes.len != x.len { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
    var ymin = lows[0usize]
    var ymax = highs[0usize]
    var step = 1.0f32
    if x.len > 1usize { step = x[1usize] - x[0usize] }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(opens[i]) || !finite(highs[i]) || !finite(lows[i]) || !finite(closes[i]) || lows[i] > opens[i] || lows[i] > closes[i] || highs[i] < opens[i] || highs[i] < closes[i] { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
        if i > 0usize {
            let gap = x[i] - x[i - 1usize]
            if !finite(gap) || gap <= 0.0 { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
            if gap < step { step = gap }
        }
        if lows[i] < ymin { ymin = lows[i] }
        if highs[i] > ymax { ymax = highs[i] }
        i += 1usize
    }
    let xmin = x[0usize] - step * 0.5
    let xmax = x[x.len - 1usize] + step * 0.5
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(xmin) || !finite(xmax) || !(xmax > xmin) || !finite(ymin) || !finite(ymax) || !(ymax > ymin) { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
    ret (xmin, xmax, ymin, ymax, step, ok)
}

fn price_y(value: f32, ymin: f32, ymax: f32, bounds: geometry.Rect) -> f32 {
    ret bounds.y + bounds.height * (1.0 - (value - ymin) / (ymax - ymin))
}

// Wicks, rising bodies and falling bodies are separate borrowed-colour layers.
// Zero-height (doji) bodies get a horizontal stroke instead of disappearing.
fn candlestick(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32, bounds: geometry.Rect, body_fraction: f32, wicks: []Segment, rising: []geometry.Rect, falling: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(body_fraction) || body_fraction <= 0.0 || body_fraction >= 1.0 { ret (zero, Invalid) }
    let (xmin, xmax, ymin, ymax, step, domain_error) = ohlc_domain(x, opens, highs, lows, closes)
    if domain_error != ok { ret (zero, domain_error) }
    if wicks.len / 2usize < x.len || rising.len < x.len || falling.len < x.len || layers.len < 3usize { ret (zero, TooLarge) }
    let width = bounds.width * step / (xmax - xmin) * body_fraction
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var up = 0usize
    var down = 0usize
    var strokes = 0usize
    var i = 0usize
    while i < x.len {
        let center = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let high_y = price_y(highs[i], ymin, ymax, bounds)
        let low_y = price_y(lows[i], ymin, ymax, bounds)
        let open_y = price_y(opens[i], ymin, ymax, bounds)
        let close_y = price_y(closes[i], ymin, ymax, bounds)
        if !finite(center) || !finite(high_y) || !finite(low_y) || !finite(open_y) || !finite(close_y) { ret (zero, Invalid) }
        wicks[strokes] = Segment { from: Coord { x: center, y: high_y }, to: Coord { x: center, y: low_y } }
        strokes += 1usize
        if opens[i] == closes[i] {
            wicks[strokes] = Segment { from: Coord { x: center - width * 0.5, y: open_y }, to: Coord { x: center + width * 0.5, y: open_y } }
            strokes += 1usize
        } else if closes[i] > opens[i] {
            rising[up] = geometry.rect(center - width * 0.5, close_y, width, open_y - close_y)
            up += 1usize
        } else {
            falling[down] = geometry.rect(center - width * 0.5, open_y, width, close_y - open_y)
            down += 1usize
        }
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Rug, coords: zero, segments: wicks[..strokes], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    layers[1usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rising[..up], x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    layers[2usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: falling[..down], x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    ret (layers[..3usize], ok)
}

// One stem plus left-open and right-close ticks per observation.
fn ohlc(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32, bounds: geometry.Rect, tick_fraction: f32, lines: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(tick_fraction) || tick_fraction <= 0.0 || tick_fraction >= 1.0 { ret (zero, Invalid) }
    let (xmin, xmax, ymin, ymax, step, domain_error) = ohlc_domain(x, opens, highs, lows, closes)
    if domain_error != ok { ret (zero, domain_error) }
    if lines.len / 3usize < x.len { ret (zero, TooLarge) }
    let half = bounds.width * step / (xmax - xmin) * tick_fraction * 0.5
    if !finite(half) || half <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < x.len {
        let center = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let high_y = price_y(highs[i], ymin, ymax, bounds)
        let low_y = price_y(lows[i], ymin, ymax, bounds)
        let open_y = price_y(opens[i], ymin, ymax, bounds)
        let close_y = price_y(closes[i], ymin, ymax, bounds)
        if !finite(center) || !finite(high_y) || !finite(low_y) || !finite(open_y) || !finite(close_y) { ret (zero, Invalid) }
        let first = 3usize * i
        lines[first] = Segment { from: Coord { x: center, y: high_y }, to: Coord { x: center, y: low_y } }
        lines[first + 1usize] = Segment { from: Coord { x: center - half, y: open_y }, to: Coord { x: center, y: open_y } }
        lines[first + 2usize] = Segment { from: Coord { x: center, y: close_y }, to: Coord { x: center + half, y: close_y } }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: lines[..3usize * x.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

fn grouped_bars(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Invalid) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var ymin = 0.0f32
    var ymax = 0.0f32
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, Invalid) }
        if values[i] < ymin { ymin = values[i] }
        if values[i] > ymax { ymax = values[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin = -0.5
        ymax = 0.5
    }
    let cell = bounds.width / f32(categories)
    let width = cell * 0.8 / f32(series)
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var category = 0usize
    while category < categories {
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            let baseline_y = bounds.y + bounds.height - mapped(0.0, ymin, ymax, 0.0, bounds.height)
            let value_y = bounds.y + bounds.height - mapped(value, ymin, ymax, 0.0, bounds.height)
            var top = baseline_y
            var bottom = value_y
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[column * categories + category] = geometry.rect(bounds.x + cell * f32(category) + cell * 0.1 + width * f32(column), top, width, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    ret (bar_layers(categories, series, bars, layers, ymin, ymax), ok)
}

// Positive and negative values stack away from zero independently. With
// normalize=true, every category must have a positive total and no negatives.
fn stacked_bars(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, normalize: bool, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Invalid) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var ymin = 0.0f64
    var ymax = 0.0f64
    var category = 0usize
    while category < categories {
        var positive = 0.0f64
        var negative = 0.0f64
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            if !finite(value) || (normalize && value < 0.0) { ret (zero, Invalid) }
            if value >= 0.0 { positive += f64(value) } else { negative += f64(value) }
            column += 1usize
        }
        if !finite(f32(positive)) || !finite(f32(negative)) || (normalize && positive <= 0.0f64) { ret (zero, Invalid) }
        if negative < ymin { ymin = negative }
        if positive > ymax { ymax = positive }
        category += 1usize
    }
    if normalize {
        ymin = 0.0f64
        ymax = 1.0f64
    }
    if ymin == ymax {
        ymin = -0.5f64
        ymax = 0.5f64
    }
    let low = f32(ymin)
    let high = f32(ymax)
    let cell = bounds.width / f32(categories)
    let width = cell * 0.8
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    category = 0usize
    while category < categories {
        var total = 1.0f64
        if normalize {
            total = 0.0f64
            var s = 0usize
            while s < series {
                total += f64(values[category * series + s])
                s += 1usize
            }
        }
        var positive = 0.0f64
        var negative = 0.0f64
        var column = 0usize
        while column < series {
            let value = f64(values[category * series + column]) / total
            var from = positive
            if value >= 0.0f64 {
                positive += value
            } else {
                from = negative
                negative += value
            }
            var to = positive
            if value < 0.0f64 { to = negative }
            let from_y = bounds.y + bounds.height - mapped(f32(from), low, high, 0.0, bounds.height)
            let to_y = bounds.y + bounds.height - mapped(f32(to), low, high, 0.0, bounds.height)
            var top = from_y
            var bottom = to_y
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[column * categories + category] = geometry.rect(bounds.x + cell * f32(category) + cell * 0.1, top, width, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    ret (bar_layers(categories, series, bars, layers, low, high), ok)
}

// Variable-width columns make each cell area proportional to its value.
// Input is category-major; output is series-major for caller-selected colours.
fn mekko(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, totals: []f64, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Empty) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if totals.len < categories || bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var grand = 0.0f64
    var category = 0usize
    while category < categories {
        var total = 0.0f64
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            total += f64(value)
            column += 1usize
        }
        if !finite(f32(total)) { ret (zero, Invalid) }
        totals[category] = total
        grand += total
        category += 1usize
    }
    if !finite(f32(grand)) { ret (zero, Invalid) }
    if grand <= 0.0f64 { ret (zero, Empty) }
    var cumulative = 0.0f64
    category = 0usize
    while category < categories {
        let left = bounds.x + bounds.width * f32(cumulative / grand)
        cumulative += totals[category]
        let right = bounds.x + bounds.width * f32(cumulative / grand)
        var stacked = 0.0f64
        var column = 0usize
        while column < series {
            let value = f64(values[category * series + column])
            var top = bounds.y + bounds.height
            var bottom = top
            if totals[category] > 0.0f64 {
                bottom = bounds.y + bounds.height * (1.0 - f32(stacked / totals[category]))
                stacked += value
                top = bounds.y + bounds.height * (1.0 - f32(stacked / totals[category]))
            }
            if !finite(left) || !finite(right) || !finite(top) || !finite(bottom) || (totals[category] > 0.0f64 && right <= left) || (value > 0.0f64 && bottom <= top) { ret (zero, Invalid) }
            bars[column * categories + category] = geometry.rect(left, top, right - left, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    let made = bar_layers(categories, series, bars, layers, 0.0, 1.0)
    var i = 0usize
    while i < made.len {
        layers[i].x_max = 1.0
        i += 1usize
    }
    ret (made, ok)
}

// Contingency-table spine: each column width follows its marginal count and
// each vertical stack follows the conditional outcome mix. Output rectangles
// are category-major so each Bar layer can take an independent category colour.
// With zero gutter, every cell area is exactly count / grand total.
fn spine_plot(counts: []const f64, columns: usize, bounds: geometry.Rect, gutter: f32, column_totals: []f64, bars: []geometry.Rect, layers: []Layout) -> (SpineLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || counts.len % columns != 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(gutter) || gutter < 0.0 { ret (zero, Invalid) }
    let categories = counts.len / columns
    if column_totals.len < columns || bars.len < counts.len || layers.len < categories { ret (zero, TooLarge) }
    var grand = 0.0f64
    var column = 0usize
    while column < columns {
        var total = 0.0f64
        var category = 0usize
        while category < categories {
            let value = counts[column * categories + category]
            if !finite64(value) || value < 0.0f64 { ret (zero, Invalid) }
            total += value
            category += 1usize
        }
        if !finite64(total) || total <= 0.0f64 { ret (zero, Invalid) }
        column_totals[column] = total
        grand += total
        column += 1usize
    }
    if !finite64(grand) || grand <= 0.0f64 { ret (zero, Invalid) }
    var cumulative = 0.0f64
    column = 0usize
    while column < columns {
        let left = bounds.x + bounds.width * f32(cumulative / grand)
        cumulative += column_totals[column]
        let right = bounds.x + bounds.width * f32(cumulative / grand)
        let width = right - left - gutter
        if !finite(left) || !finite(right) || width <= 0.0 { ret (zero, TooLarge) }
        var stacked = 0.0f64
        var category = 0usize
        while category < categories {
            let value = counts[column * categories + category]
            let bottom = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
            stacked += value
            let top = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
            if !finite(top) || !finite(bottom) { ret (zero, Invalid) }
            bars[category * columns + column] = geometry.rect(0.0, 0.0, 0.0, 0.0)
            if value > 0.0f64 {
                let height = bottom - top - gutter
                if height <= 0.0 { ret (zero, TooLarge) }
                bars[category * columns + column] = geometry.rect(left + gutter * 0.5, top + gutter * 0.5, width, height)
            }
            category += 1usize
        }
        column += 1usize
    }
    var category = 0usize
    while category < categories {
        let first = category * columns
        layers[category] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[first..first + columns], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        category += 1usize
    }
    ret (SpineLayout { categories: layers[..categories], column_totals: column_totals[..columns], grand_total: grand }, ok)
}

// Contingency-table mosaic: tile area follows count, colour follows Pearson
// residual from independence. Input is column-major; zero cells emit no tile.
fn mosaic(counts: []const f64, columns: usize, bounds: geometry.Rect, gutter: f32, column_totals: []f64, row_totals: []f64, cells: []Cell) -> (MatrixLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || counts.len % columns != 0usize || !valid_bounds(bounds) || !finite(gutter) || gutter < 0.0 { ret (zero, Invalid) }
    let rows = counts.len / columns
    if column_totals.len < columns || row_totals.len < rows || cells.len < counts.len { ret (zero, TooLarge) }
    var row = 0usize
    while row < rows {
        row_totals[row] = 0.0f64
        row += 1usize
    }
    var grand = 0.0f64
    var column = 0usize
    while column < columns {
        var total = 0.0f64
        row = 0usize
        while row < rows {
            let value = counts[column * rows + row]
            if !finite64(value) || value < 0.0f64 { ret (zero, Invalid) }
            total += value
            row_totals[row] += value
            row += 1usize
        }
        if !finite64(total) { ret (zero, Invalid) }
        column_totals[column] = total
        grand += total
        column += 1usize
    }
    if !finite64(grand) { ret (zero, Invalid) }
    if grand <= 0.0f64 { ret (zero, Empty) }
    var cumulative = 0.0f64
    var used = 0usize
    var maximum = 0.0f32
    column = 0usize
    while column < columns {
        let left = bounds.x + bounds.width * f32(cumulative / grand)
        cumulative += column_totals[column]
        let right = bounds.x + bounds.width * f32(cumulative / grand)
        var stacked = 0.0f64
        row = 0usize
        while row < rows {
            let value = counts[column * rows + row]
            if value > 0.0f64 {
                let bottom = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
                stacked += value
                let top = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
                let expected = (column_totals[column] / grand) * row_totals[row]
                if expected <= 0.0f64 { ret (zero, Invalid) }
                let residual = f32((value - expected) / math.sqrt[f64](expected))
                let width = right - left - gutter
                let height = bottom - top - gutter
                if !finite(residual) || !finite(left) || !finite(top) || !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
                cells[used] = Cell { rect: geometry.rect(left + gutter / 2.0, top + gutter / 2.0, width, height), value: residual }
                var magnitude = residual
                if magnitude < 0.0 { magnitude = -magnitude }
                if magnitude > maximum { maximum = magnitude }
                used += 1usize
            }
            row += 1usize
        }
        column += 1usize
    }
    if maximum == 0.0 { maximum = 1.0 }
    ret (MatrixLayout { kind: .Mosaic, cells: cells[..used], columns: columns, rows: rows, value_min: -maximum, value_max: maximum }, ok)
}

// Cohen-Friendly association plot: rectangle area is proportional to the
// observed-minus-expected count. Input is column-major; output tiles are
// compact row-major. Each row has its own independence baseline.
fn association(counts: []const f64, columns: usize, bounds: geometry.Rect, space: f32, column_totals: []f64, row_totals: []f64, cells: []Cell, baselines: []Segment) -> (MatrixLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || counts.len % columns != 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(space) || space < 0.0 || space >= 1.0 { ret (zero, Invalid) }
    let rows = counts.len / columns
    if column_totals.len < columns || row_totals.len < rows || cells.len < counts.len || baselines.len < rows { ret (zero, TooLarge) }
    var row = 0usize
    while row < rows {
        row_totals[row] = 0.0f64
        row += 1usize
    }
    var grand = 0.0f64
    var column = 0usize
    while column < columns {
        var total = 0.0f64
        row = 0usize
        while row < rows {
            let value = counts[column * rows + row]
            if !finite64(value) || value < 0.0f64 { ret (zero, Invalid) }
            total += value
            row_totals[row] += value
            row += 1usize
        }
        if !finite64(total) { ret (zero, Invalid) }
        column_totals[column] = total
        grand += total
        column += 1usize
    }
    if !finite(f32(grand)) { ret (zero, Invalid) }
    if grand <= 0.0f64 { ret (zero, Empty) }
    var widest = 0.0f64
    var maximum = 0.0f32
    row = 0usize
    while row < rows {
        var width = 0.0f64
        column = 0usize
        while column < columns {
            let expected = (row_totals[row] / grand) * column_totals[column]
            if !finite64(expected) { ret (zero, Invalid) }
            if expected <= 0.0f64 && counts[column * rows + row] > 0.0f64 { ret (zero, Invalid) }
            if expected > 0.0f64 {
                let root = math.sqrt[f64](expected)
                let residual = f32((counts[column * rows + row] - expected) / root)
                if !finite(residual) { ret (zero, Invalid) }
                width += root
                var magnitude = residual
                if magnitude < 0.0 { magnitude = -magnitude }
                if magnitude > maximum { maximum = magnitude }
            }
            column += 1usize
        }
        if !finite64(width) { ret (zero, Invalid) }
        if width > widest { widest = width }
        row += 1usize
    }
    if widest <= 0.0f64 { ret (zero, Invalid) }
    if maximum == 0.0 { maximum = 1.0 }
    let row_band = bounds.height / f32(rows)
    let horizontal = f64(bounds.width) / widest
    let vertical = row_band * 0.45 * (1.0 - space) / maximum
    if !finite(row_band) || row_band <= 0.0 || !finite64(horizontal) || !finite(vertical) || vertical <= 0.0 { ret (zero, Invalid) }
    var used = 0usize
    row = 0usize
    while row < rows {
        let baseline = bounds.y + row_band * (f32(row) + 0.5)
        if !finite(baseline) { ret (zero, Invalid) }
        baselines[row] = Segment { from: Coord { x: bounds.x, y: baseline }, to: Coord { x: bounds.x + bounds.width, y: baseline } }
        var cursor = f64(bounds.x)
        column = 0usize
        while column < columns {
            let expected = (row_totals[row] / grand) * column_totals[column]
            if expected > 0.0f64 {
                let footprint = math.sqrt[f64](expected) * horizontal
                let residual = f32((counts[column * rows + row] - expected) / math.sqrt[f64](expected))
                if residual != 0.0 {
                    let x = f32(cursor + footprint * f64(space) * 0.5f64)
                    let width = f32(footprint * f64(1.0 - space))
                    var magnitude = residual
                    if magnitude < 0.0 { magnitude = -magnitude }
                    let height = vertical * magnitude
                    var y = baseline
                    if residual > 0.0 { y -= height }
                    if !finite(x) || !finite(y) || !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
                    cells[used] = Cell { rect: geometry.rect(x, y, width, height), value: residual }
                    used += 1usize
                }
                cursor += footprint
            }
            column += 1usize
        }
        row += 1usize
    }
    ret (MatrixLayout { kind: .Association, cells: cells[..used], columns: columns, rows: rows, value_min: -maximum, value_max: maximum }, ok)
}

fn fourfold_share(log_odds: f64) -> f64 {
    if log_odds >= 0.0f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - log_odds * 0.5f64)) }
    let smaller = math.exp[f64](log_odds * 0.5f64)
    ret smaller / (1.0f64 + smaller)
}

// One 2x2 stratum in column-major order: TL, BL, TR, BR. Equal-margin
// standardization retains the odds ratio; quarter-circle area follows fit.
// Confidence arcs use a Wald interval with 0.5 continuity correction for zeros.
fn fourfold(counts: []const f64, bounds: geometry.Rect, confidence: f64, points: []Coord, ring_segments: []Segment, wedges: []Layout) -> (FourfoldLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if counts.len != 4usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite64(confidence) || confidence < 0.0f64 || confidence >= 1.0f64 { ret (zero, Invalid) }
    if points.len < 72usize || wedges.len < 4usize || (confidence > 0.0f64 && ring_segments.len < 128usize) { ret (zero, TooLarge) }
    var total = 0.0f64
    var any_zero = false
    var i = 0usize
    while i < 4usize {
        if !finite64(counts[i]) || counts[i] < 0.0f64 { ret (zero, Invalid) }
        if counts[i] == 0.0f64 { any_zero = true }
        total += counts[i]
        i += 1usize
    }
    if !finite(f32(total)) { ret (zero, Invalid) }
    if total <= 0.0f64 { ret (zero, Empty) }
    var corrected: [4]f64 = zero
    var se_squared = 0.0f64
    i = 0usize
    while i < 4usize {
        corrected[i] = counts[i]
        if any_zero { corrected[i] += 0.5f64 }
        se_squared += 1.0f64 / corrected[i]
        i += 1usize
    }
    let log_odds = math.log[f64](corrected[0usize]) + math.log[f64](corrected[3usize]) - math.log[f64](corrected[1usize]) - math.log[f64](corrected[2usize])
    let odds_ratio = math.exp[f64](log_odds)
    if !finite64(log_odds) || !finite64(odds_ratio) || odds_ratio <= 0.0f64 || !finite64(se_squared) { ret (zero, Invalid) }
    var delta = 0.0f64
    if confidence > 0.0f64 { delta = special.normal_quantile((1.0f64 + confidence) * 0.5f64) * math.sqrt[f64](se_squared) }
    if !finite64(delta) { ret (zero, Invalid) }
    let ci_low = math.exp[f64](log_odds - delta)
    let ci_high = math.exp[f64](log_odds + delta)
    if !finite64(ci_low) || !finite64(ci_high) || ci_low <= 0.0f64 || ci_high <= 0.0f64 { ret (zero, Invalid) }
    let radius = f64(bounds.width) * 0.5f64
    var max_radius = radius
    if bounds.height < bounds.width { max_radius = f64(bounds.height) * 0.5f64 }
    let cx = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let cy = f64(bounds.y) + f64(bounds.height) * 0.5f64
    let starts = [4]f64{ 90.0, 180.0, 0.0, 270.0 }
    let fit = fourfold_share(log_odds)
    var used = 0usize
    i = 0usize
    while i < 4usize {
        var share = fit
        if i == 1usize || i == 2usize { share = 1.0f64 - fit }
        let r = max_radius * math.sqrt[f64](share)
        let first = used
        points[used] = Coord { x: f32(cx), y: f32(cy) }
        used += 1usize
        var j = 0usize
        while j <= 16usize {
            let angle = (starts[i] + 90.0f64 * f64(j) / 16.0f64) * 0.017453292519943295f64
            let x = f32(cx + r * math.cos[f64](angle))
            let y = f32(cy - r * math.sin[f64](angle))
            if !finite(x) || !finite(y) { ret (zero, Invalid) }
            points[used] = Coord { x: x, y: y }
            used += 1usize
            j += 1usize
        }
        wedges[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    var ring_used = 0usize
    if confidence > 0.0f64 {
        var bound = 0usize
        while bound < 2usize {
            var log_limit = log_odds - delta
            if bound == 1usize { log_limit = log_odds + delta }
            let limit_share = fourfold_share(log_limit)
            i = 0usize
            while i < 4usize {
                var share = limit_share
                if i == 1usize || i == 2usize { share = 1.0f64 - limit_share }
                let r = max_radius * math.sqrt[f64](share)
                var j = 0usize
                while j < 16usize {
                    let first_angle = (starts[i] + 90.0f64 * f64(j) / 16.0f64) * 0.017453292519943295f64
                    let next_angle = (starts[i] + 90.0f64 * f64(j + 1usize) / 16.0f64) * 0.017453292519943295f64
                    let from = Coord { x: f32(cx + r * math.cos[f64](first_angle)), y: f32(cy - r * math.sin[f64](first_angle)) }
                    let to = Coord { x: f32(cx + r * math.cos[f64](next_angle)), y: f32(cy - r * math.sin[f64](next_angle)) }
                    if !finite(from.x) || !finite(from.y) || !finite(to.x) || !finite(to.y) { ret (zero, Invalid) }
                    ring_segments[ring_used] = Segment { from: from, to: to }
                    ring_used += 1usize
                    j += 1usize
                }
                i += 1usize
            }
            bound += 1usize
        }
    }
    let rings = Layout { kind: .Rug, coords: zero, segments: ring_segments[..ring_used], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    ret (FourfoldLayout { wedges: wedges[..4usize], rings: rings, odds_ratio: odds_ratio, ci_low: ci_low, ci_high: ci_high }, ok)
}

fn horizon_height(deviation: f64, lower: f64, width: f64) -> f64 {
    var height = deviation - lower
    if height < 0.0f64 { height = 0.0f64 }
    if height > width { height = width }
    ret height
}

// Fold signed deviations into caller-coloured bands. Each four-point Area
// patch covers one linear segment between threshold crossings.
// ponytail: O(samples * bands) patches; batch adjacent paths if long series become draw-bound.
fn horizon(x: []const f32, y: []const f32, origin: f32, band_width: f32, bands: usize, bounds: geometry.Rect, points: []Coord, patches: []HorizonPatch) -> ([]HorizonPatch, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || x.len < 2usize || bands == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(origin) || !finite(band_width) || band_width <= 0.0 { ret (zero, Invalid) }
    let range = f64(band_width) * f64(bands)
    let x_span = f64(x[x.len - 1usize]) - f64(x[0usize])
    if !finite64(range) || range <= 0.0f64 || !finite64(x_span) || x_span <= 0.0f64 { ret (zero, Invalid) }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(y[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, Invalid) }
        let deviation = f64(y[i]) - f64(origin)
        if !finite64(deviation) || deviation > range || deviation < 0.0f64 - range { ret (zero, Invalid) }
        i += 1usize
    }
    var used = 0usize
    var side = 0usize
    while side < 2usize {
        var level = 0usize
        while level < bands {
            let lower = f64(band_width) * f64(level)
            let upper = lower + f64(band_width)
            i = 0usize
            while i + 1usize < x.len {
                var d0 = f64(y[i]) - f64(origin)
                var d1 = f64(y[i + 1usize]) - f64(origin)
                if side == 1usize {
                    d0 = 0.0f64 - d0
                    d1 = 0.0f64 - d1
                }
                var cuts: [4]f64 = zero
                cuts[0usize] = 0.0f64
                cuts[1usize] = 1.0f64
                var count = 2usize
                if d1 != d0 {
                    let low_cut = (lower - d0) / (d1 - d0)
                    let high_cut = (upper - d0) / (d1 - d0)
                    if low_cut > 0.0f64 && low_cut < 1.0f64 {
                        cuts[count] = low_cut
                        count += 1usize
                    }
                    if high_cut > 0.0f64 && high_cut < 1.0f64 {
                        cuts[count] = high_cut
                        count += 1usize
                    }
                }
                var j = 1usize
                while j < count {
                    let selected = cuts[j]
                    var k = j
                    while k > 0usize && cuts[k - 1usize] > selected {
                        cuts[k] = cuts[k - 1usize]
                        k -= 1usize
                    }
                    cuts[k] = selected
                    j += 1usize
                }
                j = 0usize
                while j + 1usize < count {
                    let first = cuts[j]
                    let last = cuts[j + 1usize]
                    let middle = (first + last) * 0.5f64
                    if d0 + (d1 - d0) * middle > lower {
                        if used >= patches.len || used >= points.len / 4usize { ret (zero, TooLarge) }
                        let dx = f64(x[i + 1usize]) - f64(x[i])
                        let left_data = f64(x[i]) + dx * first
                        let right_data = f64(x[i]) + dx * last
                        let left = bounds.x + bounds.width * f32((left_data - f64(x[0usize])) / x_span)
                        let right = bounds.x + bounds.width * f32((right_data - f64(x[0usize])) / x_span)
                        let left_height = horizon_height(d0 + (d1 - d0) * first, lower, f64(band_width))
                        let right_height = horizon_height(d0 + (d1 - d0) * last, lower, f64(band_width))
                        let top_left = bounds.y + bounds.height * (1.0 - f32(left_height / f64(band_width)))
                        let top_right = bounds.y + bounds.height * (1.0 - f32(right_height / f64(band_width)))
                        let bottom = bounds.y + bounds.height
                        if !finite(left) || !finite(right) || !finite(top_left) || !finite(top_right) || right <= left { ret (zero, Invalid) }
                        let first_point = used * 4usize
                        points[first_point] = Coord { x: left, y: bottom }
                        points[first_point + 1usize] = Coord { x: left, y: top_left }
                        points[first_point + 2usize] = Coord { x: right, y: top_right }
                        points[first_point + 3usize] = Coord { x: right, y: bottom }
                        patches[used] = HorizonPatch { layout: Layout { kind: .Area, coords: points[first_point..first_point + 4usize], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: 0.0, y_max: band_width }, band: level, negative: side == 1usize }
                        used += 1usize
                    }
                    j += 1usize
                }
                i += 1usize
            }
            level += 1usize
        }
        side += 1usize
    }
    ret (patches[..used], ok)
}

// Consecutive observations are assigned to repeated seasonal positions.
// Each position gets a Line subseries and a horizontal mean Rug rule.
fn seasonal_subseries(values: []const f32, period: usize, bounds: geometry.Rect, segments: []Segment, means: []Segment, layers: []Layout) -> ([]Layout, Layout, err) {
    if values.len == 0usize { ret (zero, zero, Empty) }
    if period == 0usize || values.len / period < 2usize || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if segments.len < values.len - period || means.len < period || layers.len < period { ret (zero, zero, TooLarge) }
    let (raw_min, raw_max, extent_error) = extent(values)
    if extent_error != ok { ret (zero, zero, extent_error) }
    var low = f64(raw_min)
    var high = f64(raw_max)
    if low == high {
        low -= 1.0f64
        high += 1.0f64
    }
    let cycles = (values.len - 1usize) / period + 1usize
    let cell_width = f64(bounds.width) / f64(period)
    var used = 0usize
    var phase = 0usize
    while phase < period {
        let start = used
        var cycle = 0usize
        var sum = 0.0f64
        var previous: Coord = zero
        var index = phase
        while index < values.len {
            let px = f32(f64(bounds.x) + (f64(phase) + 0.1f64 + 0.8f64 * f64(cycle) / f64(cycles - 1usize)) * cell_width)
            let py = f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(values[index]) - low) / (high - low)))
            if !finite(px) || !finite(py) { ret (zero, zero, Invalid) }
            let point = Coord { x: px, y: py }
            if cycle > 0usize {
                segments[used] = Segment { from: previous, to: point }
                used += 1usize
            }
            previous = point
            sum += f64(values[index])
            cycle += 1usize
            index += period
        }
        let mean = sum / f64(cycle)
        let mean_y = f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (mean - low) / (high - low)))
        let left = f32(f64(bounds.x) + (f64(phase) + 0.1f64) * cell_width)
        let right = f32(f64(bounds.x) + (f64(phase) + 0.9f64) * cell_width)
        if !finite(mean_y) || !finite(left) || !finite(right) || right <= left { ret (zero, zero, Invalid) }
        means[phase] = Segment { from: Coord { x: left, y: mean_y }, to: Coord { x: right, y: mean_y } }
        layers[phase] = Layout { kind: .Line, coords: zero, segments: segments[start..used], bars: zero, x_min: 0.0, x_max: f32(cycles - 1usize), y_min: raw_min, y_max: raw_max }
        phase += 1usize
    }
    let mean_marks = Layout { kind: .Rug, coords: zero, segments: means[..period], bars: zero, x_min: 0.0, x_max: f32(cycles - 1usize), y_min: raw_min, y_max: raw_max }
    ret (layers[..period], mean_marks, ok)
}

fn decomposition_line(values: []const f32, first: usize, end: usize, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if first >= end || end > values.len || end - first < 2usize || segments.len < end - first - 1usize { ret (zero, Invalid) }
    var low = f64(values[first])
    var high = low
    var i = first + 1usize
    while i < end {
        if f64(values[i]) < low { low = f64(values[i]) }
        if f64(values[i]) > high { high = f64(values[i]) }
        i += 1usize
    }
    let raw_min = f32(low)
    let raw_max = f32(high)
    if low == high {
        low -= 1.0f64
        high += 1.0f64
    }
    i = first
    while i + 1usize < end {
        let left = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * f64(i) / f64(values.len - 1usize)), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(values[i]) - low) / (high - low))) }
        let right = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * f64(i + 1usize) / f64(values.len - 1usize)), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (f64(values[i + 1usize]) - low) / (high - low))) }
        if !finite(left.x) || !finite(left.y) || !finite(right.x) || !finite(right.y) { ret (zero, Invalid) }
        segments[i - first] = Segment { from: left, to: right }
        i += 1usize
    }
    ret (Layout { kind: .Line, coords: zero, segments: segments[..end - first - 1usize], bars: zero, x_min: 0.0, x_max: f32(values.len - 1usize), y_min: raw_min, y_max: raw_max }, ok)
}

// Classical additive decomposition: observed = centered-MA trend + seasonal + remainder.
// Trend and remainder are defined only on [first_valid, end_valid).
fn decomposition(values: []const f32, period: usize, bounds: geometry.Rect, gap: f32, trend: []f32, seasonal: []f32, residual: []f32, segments: []Segment, panels: []Layout) -> ([]Layout, usize, usize, err) {
    if values.len == 0usize { ret (zero, 0usize, 0usize, Empty) }
    if period < 2usize || values.len / period < 2usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, 0usize, 0usize, Invalid) }
    if trend.len < values.len || seasonal.len < values.len || residual.len < values.len || segments.len / (values.len - 1usize) < 4usize || panels.len < 4usize { ret (zero, 0usize, 0usize, TooLarge) }
    let panel_height = (bounds.height - 3.0 * gap) / 4.0
    if !finite(panel_height) || panel_height <= 0.0 || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, 0usize, 0usize, Invalid) }
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, 0usize, 0usize, Invalid) }
        i += 1usize
    }
    let radius = period / 2usize
    let first_valid = radius
    let end_valid = values.len - radius
    i = first_valid
    while i < end_valid {
        var weighted = 0.0f64
        var j = i - radius
        while j <= i + radius {
            var weight = 1.0f64
            if period % 2usize == 0usize && (j == i - radius || j == i + radius) { weight = 0.5f64 }
            weighted += f64(values[j]) * weight
            j += 1usize
        }
        trend[i] = f32(weighted / f64(period))
        if !finite(trend[i]) { ret (zero, 0usize, 0usize, Invalid) }
        i += 1usize
    }
    var season_total = 0.0f64
    var phase = 0usize
    while phase < period {
        var sum = 0.0f64
        var count = 0usize
        i = phase
        while i < end_valid {
            if i >= first_valid {
                sum += f64(values[i]) - f64(trend[i])
                count += 1usize
            }
            i += period
        }
        if count == 0usize { ret (zero, 0usize, 0usize, Invalid) }
        seasonal[phase] = f32(sum / f64(count))
        if !finite(seasonal[phase]) { ret (zero, 0usize, 0usize, Invalid) }
        season_total += f64(seasonal[phase])
        phase += 1usize
    }
    let season_mean = season_total / f64(period)
    i = 0usize
    while i < period {
        seasonal[i] = f32(f64(seasonal[i]) - season_mean)
        if !finite(seasonal[i]) { ret (zero, 0usize, 0usize, Invalid) }
        i += 1usize
    }
    while i < values.len {
        seasonal[i] = seasonal[i % period]
        i += 1usize
    }
    i = first_valid
    while i < end_valid {
        residual[i] = values[i] - trend[i] - seasonal[i]
        if !finite(residual[i]) { ret (zero, 0usize, 0usize, Invalid) }
        i += 1usize
    }
    var used = 0usize
    var panel = 0usize
    while panel < 4usize {
        var source = values
        var first = 0usize
        var end = values.len
        if panel == 1usize {
            source = trend[..values.len]
            first = first_valid
            end = end_valid
        }
        if panel == 2usize { source = seasonal[..values.len] }
        if panel == 3usize {
            source = residual[..values.len]
            first = first_valid
            end = end_valid
        }
        let panel_bounds = geometry.rect(bounds.x, bounds.y + f32(panel) * (panel_height + gap), bounds.width, panel_height)
        let (marks, mark_error) = decomposition_line(source, first, end, panel_bounds, segments[used..])
        if mark_error != ok { ret (zero, 0usize, 0usize, mark_error) }
        panels[panel] = marks
        used += marks.segments.len
        panel += 1usize
    }
    ret (panels[..4usize], first_valid, end_valid, ok)
}

// Biased sample ACF and Durbin-Levinson PACF, with paired zero-centered stem panels.
// The ACF includes lag zero; PACF stems begin at lag one.
fn correlogram(values: []const f32, max_lag: usize, bounds: geometry.Rect, gap: f32, acf: []f64, pacf: []f64, coefficients: []f64, next: []f64, stems: []Segment, guides: []Segment, panels: []Layout) -> ([]Layout, Layout, err) {
    if values.len == 0usize { ret (zero, zero, Empty) }
    if values.len < 4usize || max_lag == 0usize || max_lag >= values.len || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, zero, Invalid) }
    if acf.len <= max_lag || pacf.len <= max_lag || coefficients.len <= max_lag || next.len <= max_lag || stems.len == 0usize || max_lag > (stems.len - 1usize) / 2usize || guides.len < 6usize || panels.len < 2usize { ret (zero, zero, TooLarge) }
    let panel_height = (bounds.height - gap) * 0.5
    if !finite(panel_height) || panel_height <= 0.0 || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(f32(max_lag)) { ret (zero, zero, Invalid) }
    var mean = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, zero, Invalid) }
        mean += f64(values[i])
        i += 1usize
    }
    mean /= f64(values.len)
    var variance = 0.0f64
    i = 0usize
    while i < values.len {
        let delta = f64(values[i]) - mean
        variance += delta * delta
        i += 1usize
    }
    if variance <= 0.0f64 || !finite64(variance) { ret (zero, zero, Invalid) }
    acf[0usize] = 1.0f64
    pacf[0usize] = 1.0f64
    // ponytail: direct O(n * lags) covariance; use FFT only if long lag windows need it.
    var lag = 1usize
    while lag <= max_lag {
        var covariance = 0.0f64
        i = lag
        while i < values.len {
            covariance += (f64(values[i]) - mean) * (f64(values[i - lag]) - mean)
            i += 1usize
        }
        acf[lag] = covariance / variance
        if !finite64(acf[lag]) { ret (zero, zero, Invalid) }
        lag += 1usize
    }
    var prediction_variance = 1.0f64
    lag = 1usize
    while lag <= max_lag {
        if prediction_variance <= 0.0f64 { ret (zero, zero, Invalid) }
        var numerator = acf[lag]
        var j = 1usize
        while j < lag {
            numerator -= coefficients[j] * acf[lag - j]
            j += 1usize
        }
        let reflection = numerator / prediction_variance
        if !finite64(reflection) || reflection <= -1.0f64 || reflection >= 1.0f64 { ret (zero, zero, Invalid) }
        j = 1usize
        while j < lag {
            next[j] = coefficients[j] - reflection * coefficients[lag - j]
            j += 1usize
        }
        next[lag] = reflection
        j = 1usize
        while j <= lag {
            coefficients[j] = next[j]
            j += 1usize
        }
        pacf[lag] = reflection
        prediction_variance *= 1.0f64 - reflection * reflection
        lag += 1usize
    }
    let confidence = 1.96f64 / math.sqrt[f64](f64(values.len))
    var used = 0usize
    var panel = 0usize
    while panel < 2usize {
        let top = bounds.y + f32(panel) * (panel_height + gap)
        let baseline = top + panel_height * 0.5
        let start = used
        lag = panel
        while lag <= max_lag {
            var correlation = acf[lag]
            if panel == 1usize { correlation = pacf[lag] }
            let x = f32(f64(bounds.x) + f64(bounds.width) * f64(lag) / f64(max_lag))
            let y = f32(f64(baseline) - f64(panel_height) * correlation * 0.5f64)
            if !finite(x) || !finite(y) { ret (zero, zero, Invalid) }
            stems[used] = Segment { from: Coord { x: x, y: baseline }, to: Coord { x: x, y: y } }
            used += 1usize
            lag += 1usize
        }
        panels[panel] = Layout { kind: .Rug, coords: zero, segments: stems[start..used], bars: zero, x_min: 0.0, x_max: f32(max_lag), y_min: -1.0, y_max: 1.0 }
        var rule = 0usize
        while rule < 3usize {
            var level = 0.0f64
            if rule == 1usize { level = confidence }
            if rule == 2usize { level = -confidence }
            let y = f32(f64(baseline) - f64(panel_height) * level * 0.5f64)
            guides[panel * 3usize + rule] = Segment { from: Coord { x: bounds.x, y: y }, to: Coord { x: bounds.x + bounds.width, y: y } }
            rule += 1usize
        }
        panel += 1usize
    }
    let guide_marks = Layout { kind: .Rug, coords: zero, segments: guides[..6usize], bars: zero, x_min: 0.0, x_max: f32(max_lag), y_min: -1.0, y_max: 1.0 }
    ret (panels[..2usize], guide_marks, ok)
}

// Classical empirical semivariogram: one half of the mean squared value
// difference for pairs in each (lower, upper] distance bin.
fn variogram(x: []const f32, y: []const f32, values: []const f32, cutoff: f32, bounds: geometry.Rect, pair_counts: []u64, distances: []f64, semivariances: []f64, points: []Coord) -> (Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if values.len < 2usize || x.len != values.len || y.len != values.len || pair_counts.len == 0usize || !finite(cutoff) || cutoff <= 0.0 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if distances.len < pair_counts.len || semivariances.len < pair_counts.len || points.len < pair_counts.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        if !finite(x[i]) || !finite(y[i]) || !finite(values[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < pair_counts.len {
        pair_counts[i] = 0u64
        distances[i] = 0.0f64
        semivariances[i] = 0.0f64
        i += 1usize
    }
    // ponytail: O(n²) pair scan; add a spatial index if large point sets demand it.
    i = 0usize
    while i < values.len {
        var j = i + 1usize
        while j < values.len {
            let dx = f64(x[i]) - f64(x[j])
            let dy = f64(y[i]) - f64(y[j])
            let distance = math.sqrt[f64](dx * dx + dy * dy)
            if distance <= f64(cutoff) {
                var bin = usize(math.ceil[f64](distance * f64(pair_counts.len) / f64(cutoff)))
                if bin > 0usize { bin -= 1usize }
                if bin >= pair_counts.len { bin = pair_counts.len - 1usize }
                let difference = f64(values[i]) - f64(values[j])
                pair_counts[bin] += 1u64
                distances[bin] += distance
                semivariances[bin] += 0.5f64 * difference * difference
                if !finite64(distances[bin]) || !finite64(semivariances[bin]) { ret (zero, Invalid) }
            }
            j += 1usize
        }
        i += 1usize
    }
    var maximum = 0.0f64
    var used = 0usize
    i = 0usize
    while i < pair_counts.len {
        if pair_counts[i] > 0u64 {
            distances[i] /= f64(pair_counts[i])
            semivariances[i] /= f64(pair_counts[i])
            if semivariances[i] > maximum { maximum = semivariances[i] }
            used += 1usize
        }
        i += 1usize
    }
    if used == 0usize { ret (zero, Empty) }
    if maximum == 0.0f64 { maximum = 1.0f64 }
    let high = f32(maximum)
    if !finite(high) { ret (zero, Invalid) }
    used = 0usize
    i = 0usize
    while i < pair_counts.len {
        if pair_counts[i] > 0u64 {
            let px = f32(f64(bounds.x) + f64(bounds.width) * distances[i] / f64(cutoff))
            let py = f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - semivariances[i] / maximum))
            if !finite(px) || !finite(py) { ret (zero, Invalid) }
            points[used] = Coord { x: px, y: py }
            used += 1usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Scatter, coords: points[..used], segments: zero, bars: zero, x_min: 0.0, x_max: cutoff, y_min: 0.0, y_max: high }, ok)
}

// Two nonnegative age series diverge from a shared central label gutter.
// Input rows run from youngest (bottom) to oldest (top).
fn population_pyramid(left: []const f32, right: []const f32, bounds: geometry.Rect, gutter: f32, row_gap: f32, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if left.len == 0usize { ret (zero, Empty) }
    if left.len != right.len || !valid_bounds(bounds) || !finite(gutter) || !finite(row_gap) || gutter < 0.0 || gutter >= bounds.width || row_gap < 0.0 { ret (zero, Invalid) }
    if left.len > bars.len / 2usize || layers.len < 2usize { ret (zero, TooLarge) }
    let slot = bounds.height / f32(left.len)
    let half = (bounds.width - gutter) * 0.5
    if !finite(slot) || !finite(half) || slot <= row_gap || half <= 0.0 { ret (zero, Invalid) }
    var maximum = 0.0f32
    var i = 0usize
    while i < left.len {
        if !finite(left[i]) || !finite(right[i]) || left[i] < 0.0 || right[i] < 0.0 { ret (zero, Invalid) }
        if left[i] > maximum { maximum = left[i] }
        if right[i] > maximum { maximum = right[i] }
        i += 1usize
    }
    if maximum <= 0.0 { ret (zero, Invalid) }
    let center = bounds.x + bounds.width * 0.5
    if !finite(center) { ret (zero, Invalid) }
    i = 0usize
    while i < left.len {
        let left_width = half * f32(f64(left[i]) / f64(maximum))
        let right_width = half * f32(f64(right[i]) / f64(maximum))
        let y = bounds.y + bounds.height - slot * f32(i + 1usize) + row_gap * 0.5
        if !finite(left_width) || !finite(right_width) || !finite(y) || !finite(center - gutter * 0.5 - left_width) { ret (zero, Invalid) }
        bars[i] = geometry.rect(center - gutter * 0.5 - left_width, y, left_width, slot - row_gap)
        bars[left.len + i] = geometry.rect(center + gutter * 0.5, y, right_width, slot - row_gap)
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..left.len], x_min: 0.0 - maximum, x_max: maximum, y_min: 0.0, y_max: f32(left.len) }
    layers[1usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[left.len..left.len * 2usize], x_min: 0.0 - maximum, x_max: maximum, y_min: 0.0, y_max: f32(left.len) }
    ret (layers[..2usize], ok)
}

// Equal-width bins, left-closed/right-open except the last bin (which includes
// the maximum). Counts and rectangles are caller-owned; bars touch edge to edge.
fn histogram(values: []const f32, bounds: geometry.Rect, counts: []u64, bars: []geometry.Rect) -> (Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if counts.len == 0usize || counts.len != bars.len { ret (zero, Invalid) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < counts.len {
        counts[i] = 0u64
        i += 1usize
    }
    if raw_min == raw_max {
        counts[counts.len / 2usize] = u64(values.len)
    } else {
        let span = f64(xmax) - f64(xmin)
        i = 0usize
        while i < values.len {
            var bin = counts.len - 1usize
            if values[i] < xmax {
                bin = usize((f64(values[i]) - f64(xmin)) / span * f64(counts.len))
                if bin >= counts.len { bin = counts.len - 1usize }
            }
            counts[bin] += 1u64
            i += 1usize
        }
    }
    var tallest = 0u64
    i = 0usize
    while i < counts.len {
        if counts[i] > tallest { tallest = counts[i] }
        i += 1usize
    }
    let bar_width = bounds.width / f32(counts.len)
    i = 0usize
    while i < counts.len {
        let height = bounds.height * f32(counts[i]) / f32(tallest)
        bars[i] = geometry.rect(bounds.x + f32(i) * bar_width, bounds.y + bounds.height - height, bar_width, height)
        i += 1usize
    }
    ret (Layout { kind: .Histogram, coords: zero, segments: zero, bars: bars, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(tallest) }, ok)
}

// A scatter panel with x frequency above and y frequency to its right.
// Both marginal domains use the exact same constant-data expansion as scatter.
fn marginal_histogram(x: []const f32, y: []const f32, bounds: geometry.Rect, top_height: f32, right_width: f32, gap: f32, points: []Coord, x_counts: []u64, x_bars: []geometry.Rect, y_counts: []u64, y_bars: []geometry.Rect) -> (MarginalHistogramLayout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || !valid_bounds(bounds) || !finite(top_height) || !finite(right_width) || !finite(gap) || top_height <= 0.0 || right_width <= 0.0 || gap < 0.0 { ret (zero, Invalid) }
    if points.len < x.len { ret (zero, TooLarge) }
    if x_counts.len == 0usize || y_counts.len == 0usize || x_counts.len != x_bars.len || y_counts.len != y_bars.len { ret (zero, Invalid) }
    let top_bounds = geometry.rect(bounds.x, bounds.y - gap - top_height, bounds.width, top_height)
    let right_x = bounds.x + bounds.width + gap
    if !finite(top_bounds.y) || !finite(right_x) { ret (zero, Invalid) }
    let series = spec(.Scatter, bounds, x, y)
    let (scatter_marks, scatter_error) = layout(&series, points, zero, zero)
    if scatter_error != ok { ret (zero, scatter_error) }
    let (top_marks, top_error) = histogram(x, top_bounds, x_counts, x_bars)
    if top_error != ok { ret (zero, top_error) }
    let virtual_bounds = geometry.rect(0.0, 0.0, bounds.height, right_width)
    let (right_raw, right_error) = histogram(y, virtual_bounds, y_counts, y_bars)
    if right_error != ok { ret (zero, right_error) }
    let slot = bounds.height / f32(y_counts.len)
    var i = 0usize
    while i < y_counts.len {
        let width = right_width - y_bars[i].y
        let y_top = bounds.y + bounds.height - f32(i + 1usize) * slot
        if !finite(width) || !finite(y_top) { ret (zero, Invalid) }
        y_bars[i] = geometry.rect(right_x, y_top, width, slot)
        i += 1usize
    }
    let right_marks = Layout { kind: .Histogram, coords: zero, segments: zero, bars: y_bars, x_min: 0.0, x_max: right_raw.y_max, y_min: right_raw.x_min, y_max: right_raw.x_max }
    ret (MarginalHistogramLayout { scatter: scatter_marks, top: top_marks, right: right_marks }, ok)
}

// Observed doses and a caller-parameterised LL.4 mean curve share a log-dose
// axis. Fitting and uncertainty intervals are separate statistical work.
fn dose_response(dose: []const f64, response: []const f64, lower: f64, upper: f64, ec50: f64, slope: f64, bounds: geometry.Rect, grid: []f64, estimates: []f64, points: []Coord, segments: []Segment) -> (DoseResponseLayout, err) {
    if dose.len == 0usize { ret (zero, Empty) }
    if dose.len != response.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if grid.len < 2usize || estimates.len < grid.len || points.len < dose.len || segments.len < grid.len - 1usize { ret (zero, TooLarge) }
    var dose_min = dose[0usize]
    var dose_max = dose[0usize]
    var ymin = lower
    var ymax = upper
    var i = 0usize
    while i < dose.len {
        if !finite64(dose[i]) || dose[i] <= 0.0f64 || !finite64(response[i]) { ret (zero, Invalid) }
        if dose[i] < dose_min { dose_min = dose[i] }
        if dose[i] > dose_max { dose_max = dose[i] }
        if response[i] < ymin { ymin = response[i] }
        if response[i] > ymax { ymax = response[i] }
        i += 1usize
    }
    if dose_min == dose_max || !finite64(ymin) || !finite64(ymax) || ymax <= ymin { ret (zero, Invalid) }
    let log_min = math.log[f64](dose_min)
    let log_span = math.log[f64](dose_max) - log_min
    let y_span = ymax - ymin
    if !finite64(log_span) || !finite64(y_span) || log_span <= 0.0f64 || y_span <= 0.0f64 || !finite(f32(dose_min)) || !finite(f32(dose_max)) || !finite(f32(ymin)) || !finite(f32(ymax)) { ret (zero, Invalid) }
    i = 0usize
    while i < dose.len {
        let px = bounds.x + bounds.width * f32((math.log[f64](dose[i]) - log_min) / log_span)
        let py = bounds.y + bounds.height * f32((ymax - response[i]) / y_span)
        if !finite(px) || !finite(py) { ret (zero, Invalid) }
        points[i] = Coord { x: px, y: py }
        i += 1usize
    }
    i = 0usize
    while i < grid.len {
        grid[i] = math.exp[f64](log_min + log_span * f64(i) / f64(grid.len - 1usize))
        let (estimate, model_error) = stat.log_logistic4(grid[i], lower, upper, ec50, slope)
        if model_error != ok { ret (zero, Invalid) }
        estimates[i] = estimate
        let px = bounds.x + bounds.width * f32(i) / f32(grid.len - 1usize)
        let py = bounds.y + bounds.height * f32((ymax - estimate) / y_span)
        if !finite(px) || !finite(py) { ret (zero, Invalid) }
        if i > 0usize {
            let previous = Coord { x: bounds.x + bounds.width * f32(i - 1usize) / f32(grid.len - 1usize), y: bounds.y + bounds.height * f32((ymax - estimates[i - 1usize]) / y_span) }
            segments[i - 1usize] = Segment { from: previous, to: Coord { x: px, y: py } }
        }
        i += 1usize
    }
    let observed = Layout { kind: .Scatter, coords: points[..dose.len], segments: zero, bars: zero, x_min: f32(dose_min), x_max: f32(dose_max), y_min: f32(ymin), y_max: f32(ymax) }
    let curve = Layout { kind: .Line, coords: zero, segments: segments[..grid.len - 1usize], bars: zero, x_min: f32(dose_min), x_max: f32(dose_max), y_min: f32(ymin), y_max: f32(ymax) }
    ret (DoseResponseLayout { observations: observed, curve: curve }, ok)
}

// Draw interval event/person-time estimates as one step per explicit interval.
fn hazard_rate(edges: []const f64, rates: []const f64, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if rates.len == 0usize { ret (zero, Empty) }
    if edges.len != rates.len + 1usize || !valid_bounds(bounds) || !finite64(edges[0usize]) || edges[0usize] < 0.0f64 { ret (zero, Invalid) }
    if segments.len < rates.len || segments.len - rates.len < rates.len - 1usize { ret (zero, TooLarge) }
    var maximum = 0.0f64
    var i = 0usize
    while i < rates.len {
        if !finite64(edges[i + 1usize]) || edges[i + 1usize] <= edges[i] || !finite64(rates[i]) || rates[i] < 0.0f64 { ret (zero, Invalid) }
        if rates[i] > maximum { maximum = rates[i] }
        i += 1usize
    }
    if maximum == 0.0f64 { maximum = 1.0f64 }
    let span = edges[edges.len - 1usize] - edges[0usize]
    if !finite64(span) || span <= 0.0f64 || !finite(f32(edges[0usize])) || !finite(f32(edges[edges.len - 1usize])) || !finite(f32(maximum)) { ret (zero, Invalid) }
    var used = 0usize
    i = 0usize
    while i < rates.len {
        let left_x = bounds.x + bounds.width * f32((edges[i] - edges[0usize]) / span)
        let right_x = bounds.x + bounds.width * f32((edges[i + 1usize] - edges[0usize]) / span)
        let y = bounds.y + bounds.height * f32((maximum - rates[i]) / maximum)
        if !finite(left_x) || !finite(right_x) || !finite(y) { ret (zero, Invalid) }
        if i > 0usize {
            let previous_y = bounds.y + bounds.height * f32((maximum - rates[i - 1usize]) / maximum)
            segments[used] = Segment { from: Coord { x: left_x, y: previous_y }, to: Coord { x: left_x, y: y } }
            used += 1usize
        }
        segments[used] = Segment { from: Coord { x: left_x, y: y }, to: Coord { x: right_x, y: y } }
        used += 1usize
        i += 1usize
    }
    ret (Layout { kind: .Step, coords: zero, segments: segments[..used], bars: zero, x_min: f32(edges[0usize]), x_max: f32(edges[edges.len - 1usize]), y_min: 0.0, y_max: f32(maximum) }, ok)
}

// Connect each histogram bin center, closing at zero at the outer bin edges.
fn frequency_polygon(values: []const f32, bounds: geometry.Rect, counts: []u64, bins: []geometry.Rect, segments: []Segment) -> (Layout, err) {
    let (hist, hist_error) = histogram(values, bounds, counts, bins)
    if hist_error != ok { ret (zero, hist_error) }
    if segments.len <= bins.len { ret (zero, TooLarge) }
    let baseline = bounds.y + bounds.height
    var previous = Coord { x: bounds.x, y: baseline }
    var i = 0usize
    while i < bins.len {
        let center = Coord { x: bins[i].x + bins[i].width * 0.5, y: bins[i].y }
        segments[i] = Segment { from: previous, to: center }
        previous = center
        i += 1usize
    }
    segments[i] = Segment { from: previous, to: Coord { x: bounds.x + bounds.width, y: baseline } }
    ret (Layout { kind: .FrequencyPolygon, coords: zero, segments: segments[..i + 1usize], bars: zero, x_min: hist.x_min, x_max: hist.x_max, y_min: hist.y_min, y_max: hist.y_max }, ok)
}

// Each observation is a short independent mark along the bottom x axis.
fn rug(values: []const f32, bounds: geometry.Rect, height: f32, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(height) || height <= 0.0 || height > bounds.height { ret (zero, Invalid) }
    if segments.len < values.len { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < values.len {
        let x = mapped(values[i], xmin, xmax, bounds.x, bounds.width)
        segments[i] = Segment { from: Coord { x: x, y: bounds.y + bounds.height }, to: Coord { x: x, y: bounds.y + bounds.height - height } }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: segments[..values.len], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

// Show every observation at its numeric x value with repeatable vertical jitter.
fn strip(values: []const f32, bounds: geometry.Rect, spread: f32, coords: []Coord) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(spread) || spread < 0.0 || spread > bounds.height * 0.5 { ret (zero, Invalid) }
    if coords.len < values.len { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < values.len {
        // ponytail: eleven jitter offsets repeat; use beeswarm packing when overlap matters.
        let slot = ((i % 11usize) * 7usize) % 11usize
        coords[i] = Coord { x: mapped(values[i], xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height * 0.5 + (f32(slot) - 5.0) * spread / 5.0 }
        i += 1usize
    }
    ret (Layout { kind: .Strip, coords: coords[..values.len], segments: zero, bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

// Keep exact numeric x positions while packing square marks into free y lanes.
fn beeswarm(values: []const f32, bounds: geometry.Rect, spacing: f32, coords: []Coord) -> (Layout, err) {
    if !valid_bounds(bounds) || bounds.height < 6.0 || !finite(spacing) || spacing < 6.0 { ret (zero, Invalid) }
    let (base, base_error) = strip(values, bounds, 0.0, coords)
    if base_error != ok { ret (zero, base_error) }
    let center = bounds.y + bounds.height * 0.5
    var i = 0usize
    while i < values.len {
        var placed = false
        var slot = 0usize
        // ponytail: cubic worst-case packing suits small plots; index x lanes for large clouds.
        while slot <= i && !placed {
            let distance = f32((slot + 1usize) / 2usize) * spacing
            if distance > bounds.height * 0.5 - 3.0 { ret (zero, TooLarge) }
            var y = center - distance
            if slot % 2usize == 1usize { y = center + distance }
            var blocked = false
            var j = 0usize
            while j < i && !blocked {
                let dx = coords[i].x - coords[j].x
                let dy = y - coords[j].y
                if dx > -6.0 && dx < 6.0 && dy > -6.0 && dy < 6.0 { blocked = true }
                j += 1usize
            }
            if !blocked {
                coords[i].y = y
                placed = true
            }
            slot += 1usize
        }
        if !placed { ret (zero, TooLarge) }
        i += 1usize
    }
    var marks = base
    marks.kind = .Beeswarm
    ret (marks, ok)
}

// Histogram counts become one dot per observation, stacked in each bin.
fn dot_plot(values: []const f32, bounds: geometry.Rect, spacing: f32, counts: []u64, bins: []geometry.Rect, coords: []Coord) -> (Layout, err) {
    if !finite(spacing) || spacing < 6.0 { ret (zero, Invalid) }
    if coords.len < values.len { ret (zero, TooLarge) }
    let (hist, hist_error) = histogram(values, bounds, counts, bins)
    if hist_error != ok { ret (zero, hist_error) }
    if (hist.y_max - 1.0) * spacing + 6.0 > bounds.height { ret (zero, TooLarge) }
    var used = 0usize
    var bin = 0usize
    while bin < bins.len {
        let x = bins[bin].x + bins[bin].width * 0.5
        var row = 0u64
        while row < counts[bin] {
            coords[used] = Coord { x: x, y: bounds.y + bounds.height - 3.0 - f32(row) * spacing }
            used += 1usize
            row += 1u64
        }
        bin += 1usize
    }
    ret (Layout { kind: .DotPlot, coords: coords[..used], segments: zero, bars: zero, x_min: hist.x_min, x_max: hist.x_max, y_min: 0.0, y_max: 1.0 }, ok)
}

// A textual distribution view. Values are rounded to the requested leaf unit;
// floor-based stems keep negative values ordered and the key unambiguous:
// stem * 10 * leaf_unit + leaf * leaf_unit reconstructs each rounded value.
// Row descriptors and leaf digits borrow caller-owned storage.
fn stem_and_leaf(sorted: []const f64, leaf_unit: f64, bounds: geometry.Rect, rows: []StemLeafRow, leaves: []u8) -> (StemLeafLayout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if !finite64(leaf_unit) || leaf_unit <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if leaves.len < sorted.len { ret (zero, TooLarge) }
    var row_count = 0usize
    var max_leaves = 0usize
    var current_count = 0usize
    var previous_stem = 0i64
    var i = 0usize
    while i < sorted.len {
        let scaled = sorted[i] / leaf_unit
        if !finite64(sorted[i]) || !finite64(scaled) || scaled < -1000000000000.0f64 || scaled > 1000000000000.0f64 || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        let rounded = i64(math.round[f64](scaled))
        let stem = i64(math.floor[f64](f64(rounded) / 10.0f64))
        if i == 0usize || stem != previous_stem {
            if current_count > max_leaves { max_leaves = current_count }
            current_count = 0usize
            row_count += 1usize
            previous_stem = stem
        }
        current_count += 1usize
        i += 1usize
    }
    if current_count > max_leaves { max_leaves = current_count }
    if rows.len < row_count || bounds.height / f32(row_count) < 18.0 || bounds.width < 76.0 + 18.0 * f32(max_leaves) { ret (zero, TooLarge) }
    let row_height = bounds.height / f32(row_count)
    var used = 0usize
    i = 0usize
    while i < sorted.len {
        let rounded = i64(math.round[f64](sorted[i] / leaf_unit))
        let stem = i64(math.floor[f64](f64(rounded) / 10.0f64))
        let leaf = u8(rounded - stem * 10i64)
        if i == 0usize || stem != rows[used - 1usize].stem {
            rows[used] = StemLeafRow { stem: stem, first: i, count: 0usize, baseline: bounds.y + (f32(used) + 0.5) * row_height + 3.5 }
            used += 1usize
        }
        rows[used - 1usize].count += 1usize
        leaves[i] = leaf
        i += 1usize
    }
    let divider_x = bounds.x + 57.0
    ret (StemLeafLayout {
        rows: rows[..used], leaves: leaves[..sorted.len],
        divider: Segment { from: Coord { x: divider_x, y: bounds.y }, to: Coord { x: divider_x, y: bounds.y + bounds.height } },
        leaf_start: divider_x + 19.0, leaf_step: 18.0,
        leaf_unit: leaf_unit,
    }, ok)
}

// Empirical CDF of an ascending sample. Each observation raises the step by
// 1/n; repeated values produce coincident rises at the same x coordinate.
fn ecdf(sorted: []const f32, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    if segments.len < sorted.len || segments.len - sorted.len < sorted.len - 1usize { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(sorted)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var count = 0usize
    var i = 0usize
    while i < sorted.len {
        if i > 0usize && sorted[i] < sorted[i - 1usize] { ret (zero, Invalid) }
        let x = mapped(sorted[i], xmin, xmax, bounds.x, bounds.width)
        let previous_y = bounds.y + bounds.height * (1.0 - f32(i) / f32(sorted.len))
        let next_y = bounds.y + bounds.height * (1.0 - f32(i + 1usize) / f32(sorted.len))
        if i > 0usize {
            let old_x = mapped(sorted[i - 1usize], xmin, xmax, bounds.x, bounds.width)
            segments[count] = Segment { from: Coord { x: old_x, y: previous_y }, to: Coord { x: x, y: previous_y } }
            count += 1usize
        }
        segments[count] = Segment { from: Coord { x: x, y: previous_y }, to: Coord { x: x, y: next_y } }
        count += 1usize
        i += 1usize
    }
    ret (Layout { kind: .Ecdf, coords: zero, segments: segments[..count], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

// Monte Carlo analysis consumes caller-produced model outcomes; the chart
// never chooses an input distribution or runs a model. Exact sample counts,
// empirical CDF steps and P(outcome <= threshold) share one explicit domain.
fn monte_carlo_compare(unused: *u8, left: f64, right: f64) -> i32 {
    if left < right { ret -1i32 }
    if left > right { ret 1i32 }
    ret 0i32
}

fn monte_carlo_distribution(samples: []const f64, domain_min: f64, domain_max: f64, threshold: f64, histogram_bounds: geometry.Rect, cdf_bounds: geometry.Rect, sorted: []f64, counts: []u64, bars: []geometry.Rect, cdf_segments: []Segment, threshold_rules: []Segment) -> (MonteCarloLayout, err) {
    let n = samples.len
    if n == 0usize { ret (zero, Empty) }
    let span = domain_max - domain_min
    if !finite64(domain_min) || !finite64(domain_max) || !finite64(span) || span <= 0.0f64 || !finite64(threshold) || threshold < domain_min || threshold > domain_max || !valid_bounds(histogram_bounds) || !valid_bounds(cdf_bounds) || !finite(histogram_bounds.x + histogram_bounds.width) || !finite(histogram_bounds.y + histogram_bounds.height) || !finite(cdf_bounds.x + cdf_bounds.width) || !finite(cdf_bounds.y + cdf_bounds.height) { ret (zero, Invalid) }
    let x_min = f32(domain_min)
    let x_max = f32(domain_max)
    if !finite(x_min) || !finite(x_max) || x_max <= x_min || counts.len == 0usize || counts.len != bars.len { ret (zero, Invalid) }
    if sorted.len < n || cdf_segments.len < n || cdf_segments.len - n < n - 1usize || threshold_rules.len < 2usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if !finite64(samples[i]) || samples[i] < domain_min || samples[i] > domain_max { ret (zero, Invalid) }
        sorted[i] = samples[i]
        i += 1usize
    }
    var comparison_context = 0u8
    sort.in_place_by[f64, u8](sorted[..n], &comparison_context, monte_carlo_compare)
    i = 0usize
    while i < counts.len {
        counts[i] = 0u64
        i += 1usize
    }
    var at_or_below = 0u64
    i = 0usize
    while i < n {
        let value = samples[i]
        var bin = counts.len - 1usize
        if value < domain_max {
            bin = usize((value - domain_min) / span * f64(counts.len))
            if bin >= counts.len { bin = counts.len - 1usize }
        }
        counts[bin] += 1u64
        if value <= threshold { at_or_below += 1u64 }
        i += 1usize
    }
    var peak = 0u64
    i = 0usize
    while i < counts.len {
        if counts[i] > peak { peak = counts[i] }
        i += 1usize
    }
    let slot = histogram_bounds.width / f32(counts.len)
    if !finite(slot) || slot <= 0.0f32 || !finite(f32(peak)) { ret (zero, Invalid) }
    i = 0usize
    while i < counts.len {
        let height = histogram_bounds.height * f32(counts[i]) / f32(peak)
        bars[i] = geometry.rect(histogram_bounds.x + f32(i) * slot, histogram_bounds.y + histogram_bounds.height - height, slot, height)
        i += 1usize
    }
    var used = 0usize
    i = 0usize
    while i < n {
        let x = cdf_bounds.x + cdf_bounds.width * f32((sorted[i] - domain_min) / span)
        let previous_y = cdf_bounds.y + cdf_bounds.height * (1.0f32 - f32(i) / f32(n))
        let next_y = cdf_bounds.y + cdf_bounds.height * (1.0f32 - f32(i + 1usize) / f32(n))
        if !finite(x) || !finite(previous_y) || !finite(next_y) { ret (zero, Invalid) }
        if i > 0usize {
            let old_x = cdf_bounds.x + cdf_bounds.width * f32((sorted[i - 1usize] - domain_min) / span)
            cdf_segments[used] = Segment { from: Coord { x: old_x, y: previous_y }, to: Coord { x: x, y: previous_y } }
            used += 1usize
        }
        cdf_segments[used] = Segment { from: Coord { x: x, y: previous_y }, to: Coord { x: x, y: next_y } }
        used += 1usize
        i += 1usize
    }
    let threshold_fraction = f32((threshold - domain_min) / span)
    let histogram_x = histogram_bounds.x + histogram_bounds.width * threshold_fraction
    let cdf_x = cdf_bounds.x + cdf_bounds.width * threshold_fraction
    if !finite(histogram_x) || !finite(cdf_x) { ret (zero, Invalid) }
    threshold_rules[0usize] = Segment { from: Coord { x: histogram_x, y: histogram_bounds.y }, to: Coord { x: histogram_x, y: histogram_bounds.y + histogram_bounds.height } }
    threshold_rules[1usize] = Segment { from: Coord { x: cdf_x, y: cdf_bounds.y }, to: Coord { x: cdf_x, y: cdf_bounds.y + cdf_bounds.height } }
    let histogram_marks = Layout { kind: .Histogram, coords: zero, segments: zero, bars: bars[..counts.len], x_min: x_min, x_max: x_max, y_min: 0.0f32, y_max: f32(peak) }
    let cdf_marks = Layout { kind: .Ecdf, coords: zero, segments: cdf_segments[..used], bars: zero, x_min: x_min, x_max: x_max, y_min: 0.0f32, y_max: 1.0f32 }
    let histogram_rule = Layout { kind: .Rug, coords: zero, segments: threshold_rules[..1usize], bars: zero, x_min: x_min, x_max: x_max, y_min: 0.0f32, y_max: f32(peak) }
    let cdf_rule = Layout { kind: .Rug, coords: zero, segments: threshold_rules[1usize..2usize], bars: zero, x_min: x_min, x_max: x_max, y_min: 0.0f32, y_max: 1.0f32 }
    ret (MonteCarloLayout { histogram: histogram_marks, cdf: cdf_marks, histogram_threshold: histogram_rule, cdf_threshold: cdf_rule, sorted: sorted[..n], counts: counts, at_or_below: at_or_below, probability: f64(at_or_below) / f64(n) }, ok)
}

fn box_y(value: f64, lo: f64, hi: f64, bounds: geometry.Rect) -> f32 {
    ret bounds.y + bounds.height * f32(1.0f64 - (value - lo) / (hi - lo))
}

// One vertical Tukey box: R7 quartiles, whiskers at the most extreme sample
// within 1.5 IQR, and caller-owned coordinates for values beyond the fences.
fn box_plot(sorted: []const f64, bounds: geometry.Rect, outliers: []Coord, lines: []Segment, boxes: []geometry.Rect) -> (Layout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    if lines.len < 5usize || boxes.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let (q1, first_ok) = stat.quantile(sorted, 0.25f64, .R7)
    let (median, middle_ok) = stat.quantile(sorted, 0.5f64, .R7)
    let (q3, third_ok) = stat.quantile(sorted, 0.75f64, .R7)
    if !first_ok || !middle_ok || !third_ok { ret (zero, Invalid) }
    let spread = q3 - q1
    let lower_fence = q1 - 1.5f64 * spread
    let upper_fence = q3 + 1.5f64 * spread
    var lower = sorted[0usize]
    var upper = sorted[sorted.len - 1usize]
    var outlier_count = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < lower_fence || sorted[i] > upper_fence {
            outlier_count += 1usize
        } else {
            if sorted[i] < lower || lower < lower_fence { lower = sorted[i] }
            if sorted[i] > upper || upper > upper_fence { upper = sorted[i] }
        }
        i += 1usize
    }
    if outliers.len < outlier_count { ret (zero, TooLarge) }
    var lo = sorted[0usize]
    var hi = sorted[sorted.len - 1usize]
    if lo == hi {
        lo -= 0.5f64
        hi += 0.5f64
    }
    let cx = bounds.x + bounds.width / 2.0
    let width = bounds.width * 0.36
    let cap = width * 0.5
    let low_y = box_y(lower, lo, hi, bounds)
    let q1_y = box_y(q1, lo, hi, bounds)
    let mid_y = box_y(median, lo, hi, bounds)
    let q3_y = box_y(q3, lo, hi, bounds)
    let high_y = box_y(upper, lo, hi, bounds)
    boxes[0usize] = geometry.rect(cx - width / 2.0, q3_y, width, q1_y - q3_y)
    lines[0usize] = Segment { from: Coord { x: cx, y: q1_y }, to: Coord { x: cx, y: low_y } }
    lines[1usize] = Segment { from: Coord { x: cx, y: q3_y }, to: Coord { x: cx, y: high_y } }
    lines[2usize] = Segment { from: Coord { x: cx - cap / 2.0, y: low_y }, to: Coord { x: cx + cap / 2.0, y: low_y } }
    lines[3usize] = Segment { from: Coord { x: cx - cap / 2.0, y: high_y }, to: Coord { x: cx + cap / 2.0, y: high_y } }
    lines[4usize] = Segment { from: Coord { x: cx - width / 2.0, y: mid_y }, to: Coord { x: cx + width / 2.0, y: mid_y } }
    var placed = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < lower_fence || sorted[i] > upper_fence {
            outliers[placed] = Coord { x: cx, y: box_y(sorted[i], lo, hi, bounds) }
            placed += 1usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Box, coords: outliers[..placed], segments: lines[..5usize], bars: boxes[..1usize], x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// Nested R7 letter-value ranges; depth is explicit and each tail must retain
// at least one observation. Points beyond the outer range are tail observations.
fn boxen_plot(sorted: []const f64, bounds: geometry.Rect, depth: usize, tails: []Coord, median_line: []Segment, boxes: []geometry.Rect) -> (Layout, err) {
    if sorted.len < 4usize { ret (zero, Empty) }
    if depth == 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if boxes.len < depth || median_line.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var lo = sorted[0usize]
    var hi = sorted[sorted.len - 1usize]
    if lo == hi {
        lo -= 0.5f64
        hi += 0.5f64
    }
    let cx = bounds.x + bounds.width / 2.0
    var probability = 0.25f64
    var outer_low = lo
    var outer_high = hi
    i = 0usize
    while i < depth {
        if probability * f64(sorted.len) < 1.0f64 { ret (zero, Invalid) }
        let (low, low_ok) = stat.quantile(sorted, probability, .R7)
        let (high, high_ok) = stat.quantile(sorted, 1.0f64 - probability, .R7)
        if !low_ok || !high_ok { ret (zero, Invalid) }
        let width = bounds.width * 0.72 * f32(depth - i) / f32(depth)
        let top = box_y(high, lo, hi, bounds)
        boxes[i] = geometry.rect(cx - width / 2.0, top, width, box_y(low, lo, hi, bounds) - top)
        outer_low = low
        outer_high = high
        probability *= 0.5f64
        i += 1usize
    }
    let (middle, middle_ok) = stat.quantile(sorted, 0.5f64, .R7)
    if !middle_ok { ret (zero, Invalid) }
    let median_y = box_y(middle, lo, hi, bounds)
    median_line[0usize] = Segment { from: Coord { x: boxes[0usize].x, y: median_y }, to: Coord { x: boxes[0usize].x + boxes[0usize].width, y: median_y } }
    var used = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < outer_low || sorted[i] > outer_high {
            if used >= tails.len { ret (zero, TooLarge) }
            tails[used] = Coord { x: cx, y: box_y(sorted[i], lo, hi, bounds) }
            used += 1usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Box, coords: tails[..used], segments: median_line[..1usize], bars: boxes[..depth], x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// Shared Gaussian estimate for density and violin marks. The caller owns both
// arrays; zero bandwidth selects Scott's rule.
fn kde_grid(values: []const f64, bandwidth: f64, grid: []f64, estimates: []f64) -> (f64, f64, f64, err) {
    if values.len == 0usize { ret (0.0f64, 0.0f64, 0.0f64, Empty) }
    if grid.len < 2usize || estimates.len < grid.len { ret (0.0f64, 0.0f64, 0.0f64, TooLarge) }
    var lo = values[0usize]
    var hi = lo
    var i = 0usize
    while i < values.len {
        if !finite(f32(values[i])) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    var bw = bandwidth
    if bw == 0.0f64 {
        let (chosen, has_bandwidth) = stat.kde_bandwidth(values, .Scott)
        if !has_bandwidth { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        bw = chosen
    }
    if !(bw > 0.0f64) || !finite(f32(bw)) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    lo -= 3.0f64 * bw
    hi += 3.0f64 * bw
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    i = 0usize
    while i < grid.len {
        grid[i] = lo + (hi - lo) * f64(i) / f64(grid.len - 1usize)
        i += 1usize
    }
    let density_error = stat.kde(values, bw, grid, estimates)
    if density_error != ok { ret (0.0f64, 0.0f64, 0.0f64, density_error) }
    var peak = 0.0f64
    i = 0usize
    while i < grid.len {
        if estimates[i] > peak { peak = estimates[i] }
        i += 1usize
    }
    if !(peak > 0.0f64) || !finite(f32(peak)) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    ret (lo, hi, peak, ok)
}

// Gaussian KDE on an equally spaced caller-owned grid. Zero bandwidth selects
// Scott's rule; a positive bandwidth is an explicit caller calibration.
fn density(values: []const f64, bounds: geometry.Rect, bandwidth: f64, grid: []f64, estimates: []f64, segments: []Segment) -> (Layout, err) {
    if grid.len < 2usize || segments.len < grid.len - 1usize { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (lo, hi, peak, grid_error) = kde_grid(values, bandwidth, grid, estimates)
    if grid_error != ok { ret (zero, grid_error) }
    var i = 0usize
    while i + 1usize < grid.len {
        segments[i] = Segment {
            from: Coord { x: bounds.x + bounds.width * f32(i) / f32(grid.len - 1usize), y: bounds.y + bounds.height * f32(1.0f64 - estimates[i] / peak) },
            to: Coord { x: bounds.x + bounds.width * f32(i + 1usize) / f32(grid.len - 1usize), y: bounds.y + bounds.height * f32(1.0f64 - estimates[i + 1usize] / peak) },
        }
        i += 1usize
    }
    ret (Layout { kind: .Density, coords: zero, segments: segments[..grid.len - 1usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }, ok)
}

// Groups are concatenated in `values` and drawn top-to-bottom on one KDE x
// domain. `overlap` is ridge height in row spacings; heights share one density
// scale, so unlike per-ridge normalization they retain cross-group magnitude.
fn ridgeline(values: []const f64, lengths: []const usize, bounds: geometry.Rect, bandwidth: f64, overlap: f32, grid: []f64, estimates: []f64, bandwidths: []f64, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize || lengths.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(overlap) || overlap <= 0.0 || bandwidth < 0.0f64 || !finite64(bandwidth) { ret (zero, Invalid) }
    if grid.len < 2usize || estimates.len / grid.len < lengths.len || outline.len / (grid.len + 2usize) < lengths.len || bandwidths.len < lengths.len || layers.len < lengths.len { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = lo
    var offset = 0usize
    var max_bandwidth = 0.0f64
    var group = 0usize
    while group < lengths.len {
        let count = lengths[group]
        if count == 0usize || count > values.len - offset { ret (zero, Invalid) }
        var i = offset
        while i < offset + count {
            if !finite(f32(values[i])) { ret (zero, Invalid) }
            if values[i] < lo { lo = values[i] }
            if values[i] > hi { hi = values[i] }
            i += 1usize
        }
        var bw = bandwidth
        if bw == 0.0f64 {
            let (chosen, defined) = stat.kde_bandwidth(values[offset..offset + count], .Scott)
            if !defined { ret (zero, Invalid) }
            bw = chosen
        }
        if !(bw > 0.0f64) || !finite(f32(bw)) { ret (zero, Invalid) }
        bandwidths[group] = bw
        if bw > max_bandwidth { max_bandwidth = bw }
        offset += count
        group += 1usize
    }
    if offset != values.len { ret (zero, Invalid) }
    lo -= 3.0f64 * max_bandwidth
    hi += 3.0f64 * max_bandwidth
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) { ret (zero, Invalid) }
    var i = 0usize
    while i < grid.len {
        grid[i] = lo + (hi - lo) * f64(i) / f64(grid.len - 1usize)
        i += 1usize
    }
    var peak = 0.0f64
    offset = 0usize
    group = 0usize
    while group < lengths.len {
        let first = group * grid.len
        let kde_error = stat.kde(values[offset..offset + lengths[group]], bandwidths[group], grid, estimates[first..first + grid.len])
        if kde_error != ok { ret (zero, kde_error) }
        i = first
        while i < first + grid.len {
            if estimates[i] > peak { peak = estimates[i] }
            i += 1usize
        }
        offset += lengths[group]
        group += 1usize
    }
    if !(peak > 0.0f64) || !finite(f32(peak)) { ret (zero, Invalid) }
    let spacing = bounds.height / (f32(lengths.len - 1usize) + overlap)
    let height = spacing * overlap
    if !finite(spacing) || !finite(height) || spacing <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
    group = 0usize
    while group < lengths.len {
        let baseline = bounds.y + height + spacing * f32(group)
        if !finite(baseline) { ret (zero, Invalid) }
        let first = group * (grid.len + 2usize)
        outline[first] = Coord { x: bounds.x, y: baseline }
        i = 0usize
        while i < grid.len {
            let x = bounds.x + bounds.width * f32(i) / f32(grid.len - 1usize)
            let y = baseline - height * f32(estimates[group * grid.len + i] / peak)
            if !finite(x) || !finite(y) { ret (zero, Invalid) }
            outline[first + i + 1usize] = Coord { x: x, y: y }
            i += 1usize
        }
        outline[first + grid.len + 1usize] = Coord { x: bounds.x + bounds.width, y: baseline }
        layers[group] = Layout { kind: .Area, coords: outline[first..first + grid.len + 2usize], segments: zero, bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(lengths.len) }
        group += 1usize
    }
    ret (layers[..lengths.len], ok)
}

// The same estimate mirrored around the panel center. `outline` holds the
// closed shape's left side bottom-to-top and right side top-to-bottom.
fn violin(values: []const f64, bounds: geometry.Rect, bandwidth: f64, grid: []f64, estimates: []f64, outline: []Coord) -> (Layout, err) {
    if grid.len < 2usize || outline.len / 2usize < grid.len { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (lo, hi, peak, grid_error) = kde_grid(values, bandwidth, grid, estimates)
    if grid_error != ok { ret (zero, grid_error) }
    let center = bounds.x + bounds.width / 2.0
    let half = bounds.width * 0.35
    var i = 0usize
    while i < grid.len {
        let y = bounds.y + bounds.height * f32(1.0f64 - (grid[i] - lo) / (hi - lo))
        let side = half * f32(estimates[i] / peak)
        outline[i] = Coord { x: center - side, y: y }
        outline[2usize * grid.len - 1usize - i] = Coord { x: center + side, y: y }
        i += 1usize
    }
    ret (Layout { kind: .Violin, coords: outline[..2usize * grid.len], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// A one-sided KDE silhouette anchored at the panel centre. The exposed
// baseline makes room for a box summary or raw observations on the other side.
fn half_violin(values: []const f64, bounds: geometry.Rect, bandwidth: f64, right: bool, grid: []f64, estimates: []f64, outline: []Coord) -> (Layout, err) {
    if grid.len < 2usize || outline.len < grid.len + 2usize { ret (zero, TooLarge) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    let (lo, hi, peak, grid_error) = kde_grid(values, bandwidth, grid, estimates)
    if grid_error != ok { ret (zero, grid_error) }
    let center = bounds.x + bounds.width * 0.5
    let half = bounds.width * 0.35
    outline[0usize] = Coord { x: center, y: bounds.y + bounds.height }
    var i = 0usize
    while i < grid.len {
        let y = bounds.y + bounds.height * f32(1.0f64 - (grid[i] - lo) / (hi - lo))
        let spread = half * f32(estimates[i] / peak)
        var x = center - spread
        if right { x = center + spread }
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        outline[i + 1usize] = Coord { x: x, y: y }
        i += 1usize
    }
    outline[grid.len + 1usize] = Coord { x: center, y: bounds.y }
    ret (Layout { kind: .Violin, coords: outline[..grid.len + 2usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// A half violin, all observations, and a Tukey IQR/whisker summary use the
// same KDE-extended value domain. Raw drops repeat eleven deterministic lanes;
// dense ties may overlap and can use beeswarm packing in a later variant.
fn raincloud(sorted: []const f64, bounds: geometry.Rect, bandwidth: f64, grid: []f64, estimates: []f64, outline: []Coord, drops: []Coord, whiskers: []Segment, boxes: []geometry.Rect) -> (RaincloudLayout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if drops.len < sorted.len || whiskers.len < 5usize || boxes.len == 0usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let (cloud, cloud_error) = half_violin(sorted, bounds, bandwidth, false, grid, estimates, outline)
    if cloud_error != ok { ret (zero, cloud_error) }
    let lo = grid[0usize]
    let hi = grid[grid.len - 1usize]
    let (q1, first_ok) = stat.quantile(sorted, 0.25f64, .R7)
    let (median, middle_ok) = stat.quantile(sorted, 0.5f64, .R7)
    let (q3, third_ok) = stat.quantile(sorted, 0.75f64, .R7)
    if !first_ok || !middle_ok || !third_ok { ret (zero, Invalid) }
    let lower_fence = q1 - 1.5f64 * (q3 - q1)
    let upper_fence = q3 + 1.5f64 * (q3 - q1)
    var lower = q1
    var upper = q3
    i = 0usize
    while i < sorted.len {
        if sorted[i] >= lower_fence && sorted[i] < lower { lower = sorted[i] }
        if sorted[i] <= upper_fence && sorted[i] > upper { upper = sorted[i] }
        i += 1usize
    }
    let cx = bounds.x + bounds.width * 0.56
    let width = bounds.width * 0.08
    let cap = width * 0.5
    let low_y = box_y(lower, lo, hi, bounds)
    let q1_y = box_y(q1, lo, hi, bounds)
    let median_y = box_y(median, lo, hi, bounds)
    let q3_y = box_y(q3, lo, hi, bounds)
    let high_y = box_y(upper, lo, hi, bounds)
    boxes[0usize] = geometry.rect(cx - width * 0.5, q3_y, width, q1_y - q3_y)
    whiskers[0usize] = Segment { from: Coord { x: cx, y: q1_y }, to: Coord { x: cx, y: low_y } }
    whiskers[1usize] = Segment { from: Coord { x: cx, y: q3_y }, to: Coord { x: cx, y: high_y } }
    whiskers[2usize] = Segment { from: Coord { x: cx - cap * 0.5, y: low_y }, to: Coord { x: cx + cap * 0.5, y: low_y } }
    whiskers[3usize] = Segment { from: Coord { x: cx - cap * 0.5, y: high_y }, to: Coord { x: cx + cap * 0.5, y: high_y } }
    whiskers[4usize] = Segment { from: Coord { x: cx - width * 0.5, y: median_y }, to: Coord { x: cx + width * 0.5, y: median_y } }
    i = 0usize
    while i < sorted.len {
        let lane = ((i % 11usize) * 5usize) % 11usize
        drops[i] = Coord { x: bounds.x + bounds.width * (0.66 + 0.25 * f32(lane) / 10.0), y: box_y(sorted[i], lo, hi, bounds) }
        i += 1usize
    }
    ret (RaincloudLayout {
        cloud: cloud,
        drops: Layout { kind: .Strip, coords: drops[..sorted.len], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) },
        summary: Layout { kind: .Box, coords: zero, segments: whiskers[..5usize], bars: boxes[..1usize], x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) },
    }, ok)
}

fn probability_paper_quantile(family: ProbabilityFamily, p: f64) -> f64 {
    if family == .Exponential { ret 0.0f64 - math.log[f64](1.0f64 - p) }
    ret special.normal_quantile(p)
}

fn weibull_paper(p: f64) -> f64 {
    ret math.log[f64](0.0f64 - math.log[f64](1.0f64 - p))
}

// Binomial operating-characteristic curve for one attributes sampling plan.
// The caller chooses curve resolution via `points.len`; each point is an
// acceptance probability at an evenly spaced defective fraction.
fn oc_curve(sample_size: usize, acceptance_number: usize, max_fraction: f64, bounds: geometry.Rect, points: []Coord, segments: []Segment) -> (Layout, err) {
    if sample_size == 0usize || acceptance_number > sample_size || !finite64(max_fraction) || max_fraction <= 0.0f64 || max_fraction > 1.0f64 || f32(max_fraction) <= 0.0 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if points.len < 2usize || segments.len < points.len - 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < points.len {
        let defect_fraction = max_fraction * f64(i) / f64(points.len - 1usize)
        let (probability, probability_error) = stat.binomial_acceptance_probability(sample_size, acceptance_number, defect_fraction)
        if probability_error != ok { ret (zero, Invalid) }
        let point = Coord { x: bounds.x + bounds.width * f32(i) / f32(points.len - 1usize), y: bounds.y + bounds.height * f32(1.0f64 - probability) }
        if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
        points[i] = point
        if i > 0usize { segments[i - 1usize] = Segment { from: points[i - 1usize], to: point } }
        i += 1usize
    }
    ret (Layout { kind: .PointLine, coords: points, segments: segments[..points.len - 1usize], bars: zero, x_min: 0.0, x_max: f32(max_fraction), y_min: 0.0, y_max: 1.0 }, ok)
}

// Four crossed-study components in Minitab order: total gage, repeatability,
// reproducibility, part-to-part. Each category has % variance contribution
// and % study variation (standard deviation relative to total) bars.
fn gage_rr_components(components: *const stat.GageRrComponents, bounds: geometry.Rect, bars: []geometry.Rect, percentages: []f32) -> (GageRrLayout, err) {
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite64(components.total) || components.total <= 0.0f64 || !finite64(components.gage) || !finite64(components.repeatability) || !finite64(components.operator) || !finite64(components.interaction) || !finite64(components.part) || components.gage < 0.0f64 || components.repeatability < 0.0f64 || components.operator < 0.0f64 || components.interaction < 0.0f64 || components.part < 0.0f64 { ret (zero, Invalid) }
    if bars.len < 8usize || percentages.len < 8usize { ret (zero, TooLarge) }
    let values = [4]f64{ components.gage, components.repeatability, components.operator + components.interaction, components.part }
    let bar_width = bounds.width / 11.0
    let gap = bar_width * 0.12
    var i = 0usize
    while i < 4usize {
        let ratio = values[i] / components.total
        if !finite64(ratio) || ratio < 0.0f64 || ratio > 1.0f64 { ret (zero, Invalid) }
        let contribution = f32(100.0f64 * ratio)
        let study = f32(100.0f64 * math.sqrt[f64](ratio))
        let center = bounds.x + bounds.width * (f32(i) + 0.5) / 4.0
        let left_x = center - bar_width - gap * 0.5
        let right_x = center + gap * 0.5
        percentages[i] = contribution
        percentages[4usize + i] = study
        bars[i] = geometry.rect(left_x, bounds.y + bounds.height * (1.0 - contribution / 100.0), bar_width, bounds.height * contribution / 100.0)
        bars[4usize + i] = geometry.rect(right_x, bounds.y + bounds.height * (1.0 - study / 100.0), bar_width, bounds.height * study / 100.0)
        i += 1usize
    }
    let contribution_layout = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..4usize], x_min: 0.0, x_max: 4.0, y_min: 0.0, y_max: 100.0 }
    let study_layout = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[4usize..8usize], x_min: 0.0, x_max: 4.0, y_min: 0.0, y_max: 100.0 }
    ret (GageRrLayout { contribution: contribution_layout, study_variation: study_layout, percentages: percentages[..8usize] }, ok)
}

// Two-factor multi-vari: values are outer factor, inner factor, then replicate.
// Raw readings are retained; cell means connect only within each outer group,
// while group means connect across groups. All work is caller-owned.
fn multi_vari(values: []const f64, outer_levels: usize, inner_levels: usize, replicates: usize, bounds: geometry.Rect, storage: *MultiVariStorage) -> (MultiVariLayout, err) {
    if outer_levels < 2usize || inner_levels < 2usize || replicates == 0usize || values.len == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if outer_levels > values.len / inner_levels { ret (zero, Invalid) }
    let cells = outer_levels * inner_levels
    if replicates > values.len / cells || cells * replicates != values.len { ret (zero, Invalid) }
    if storage.raw_points.len < values.len || storage.cell_points.len < cells || storage.cell_lines.len < outer_levels * (inner_levels - 1usize) || storage.group_points.len < outer_levels || storage.group_lines.len < outer_levels - 1usize || storage.cell_means.len < cells || storage.group_means.len < outer_levels { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = values[0usize]
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    if lo == hi {
        let pad = math.max[f64](1.0f64, math.abs[f64](lo) * 0.05f64)
        lo -= pad
        hi += pad
    }
    if !finite64(lo) || !finite64(hi) || !finite64(hi - lo) || hi <= lo || !finite(f32(lo)) || !finite(f32(hi)) { ret (zero, Invalid) }
    let group_width = bounds.width / f32(outer_levels)
    let cell_width = group_width / f32(inner_levels)
    let baseline = values[0usize]
    var group = 0usize
    while group < outer_levels {
        var group_sum = 0.0f64
        var level = 0usize
        while level < inner_levels {
            let cell = group * inner_levels + level
            let x = bounds.x + group_width * (f32(group) + (f32(level) + 0.5) / f32(inner_levels))
            var centered_sum = 0.0f64
            var trial = 0usize
            while trial < replicates {
                let value = values[cell * replicates + trial]
                centered_sum += value - baseline
                let offset = (f32(trial) - (f32(replicates) - 1.0) * 0.5) * cell_width * 0.3 / f32(replicates)
                storage.raw_points[cell * replicates + trial] = Coord { x: x + offset, y: bounds.y + bounds.height * f32((hi - value) / (hi - lo)) }
                trial += 1usize
            }
            if !finite64(centered_sum) { ret (zero, Invalid) }
            let cell_mean = baseline + centered_sum / f64(replicates)
            storage.cell_means[cell] = cell_mean
            group_sum += centered_sum / f64(replicates)
            let point = Coord { x: x, y: bounds.y + bounds.height * f32((hi - cell_mean) / (hi - lo)) }
            if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
            storage.cell_points[cell] = point
            if level > 0usize { storage.cell_lines[group * (inner_levels - 1usize) + level - 1usize] = Segment { from: storage.cell_points[cell - 1usize], to: point } }
            level += 1usize
        }
        if !finite64(group_sum) { ret (zero, Invalid) }
        let group_mean = baseline + group_sum / f64(inner_levels)
        storage.group_means[group] = group_mean
        let group_point = Coord { x: bounds.x + group_width * (f32(group) + 0.5), y: bounds.y + bounds.height * f32((hi - group_mean) / (hi - lo)) }
        if !finite(group_point.x) || !finite(group_point.y) { ret (zero, Invalid) }
        storage.group_points[group] = group_point
        if group > 0usize { storage.group_lines[group - 1usize] = Segment { from: storage.group_points[group - 1usize], to: group_point } }
        group += 1usize
    }
    let raw = Layout { kind: .Scatter, coords: storage.raw_points[..values.len], segments: zero, bars: zero, x_min: 0.0, x_max: f32(cells), y_min: f32(lo), y_max: f32(hi) }
    let cell_marks = Layout { kind: .Scatter, coords: storage.cell_points[..cells], segments: zero, bars: zero, x_min: 0.0, x_max: f32(cells), y_min: f32(lo), y_max: f32(hi) }
    let within = Layout { kind: .Rug, coords: zero, segments: storage.cell_lines[..outer_levels * (inner_levels - 1usize)], bars: zero, x_min: 0.0, x_max: f32(cells), y_min: f32(lo), y_max: f32(hi) }
    let between = Layout { kind: .PointLine, coords: storage.group_points[..outer_levels], segments: storage.group_lines[..outer_levels - 1usize], bars: zero, x_min: 0.0, x_max: f32(cells), y_min: f32(lo), y_max: f32(hi) }
    ret (MultiVariLayout { observations: raw, cells: cell_marks, within: within, groups: between, cell_means: storage.cell_means[..cells], group_means: storage.group_means[..outer_levels] }, ok)
}

// Raw-data main effects: factor ids are observation-major, with one id per
// factor per response. Each factor gets an independent panel and reference
// line; unequal nonempty level counts are allowed. No model is fitted.
fn main_effects(values: []const f64, factor_ids: []const usize, factor_levels: []const usize, bounds: geometry.Rect, storage: *MainEffectsStorage) -> (MainEffectsLayout, err) {
    if values.len == 0usize || factor_levels.len == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if factor_levels.len > factor_ids.len / values.len || factor_ids.len != values.len * factor_levels.len { ret (zero, Invalid) }
    var total_levels = 0usize
    var factor = 0usize
    while factor < factor_levels.len {
        let levels = factor_levels[factor]
        if levels < 2usize || levels > values.len || levels > factor_ids.len - total_levels { ret (zero, Invalid) }
        total_levels += levels
        factor += 1usize
    }
    let connections = total_levels - factor_levels.len
    if storage.points.len < total_levels || storage.lines.len < connections || storage.references.len < factor_levels.len || storage.means.len < total_levels || storage.counts.len < total_levels { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = values[0usize]
    var centered_total = 0.0f64
    var row = 0usize
    while row < values.len {
        let value = values[row]
        if !finite64(value) { ret (zero, Invalid) }
        if value < lo { lo = value }
        if value > hi { hi = value }
        centered_total += value - values[0usize]
        factor = 0usize
        while factor < factor_levels.len {
            if factor_ids[row * factor_levels.len + factor] >= factor_levels[factor] { ret (zero, Invalid) }
            factor += 1usize
        }
        row += 1usize
    }
    if !finite64(centered_total) { ret (zero, Invalid) }
    let grand_mean = values[0usize] + centered_total / f64(values.len)
    if !finite64(grand_mean) { ret (zero, Invalid) }
    if lo == hi {
        let pad = math.max[f64](1.0f64, math.abs[f64](lo) * 0.05f64)
        lo -= pad
        hi += pad
    }
    if !finite64(lo) || !finite64(hi) || !finite64(hi - lo) || hi <= lo || !finite(f32(lo)) || !finite(f32(hi)) { ret (zero, Invalid) }
    var level = 0usize
    while level < total_levels {
        storage.means[level] = 0.0f64
        storage.counts[level] = 0usize
        level += 1usize
    }
    row = 0usize
    while row < values.len {
        var offset = 0usize
        factor = 0usize
        while factor < factor_levels.len {
            let index = offset + factor_ids[row * factor_levels.len + factor]
            storage.means[index] += values[row] - values[0usize]
            storage.counts[index] += 1usize
            offset += factor_levels[factor]
            factor += 1usize
        }
        row += 1usize
    }
    let panel_width = bounds.width / f32(factor_levels.len)
    let reference_y = bounds.y + bounds.height * f32((hi - grand_mean) / (hi - lo))
    if !finite(panel_width) || !finite(reference_y) { ret (zero, Invalid) }
    var offset = 0usize
    var line = 0usize
    factor = 0usize
    while factor < factor_levels.len {
        let levels = factor_levels[factor]
        let left = bounds.x + panel_width * f32(factor)
        let right = left + panel_width
        storage.references[factor] = Segment { from: Coord { x: left, y: reference_y }, to: Coord { x: right, y: reference_y } }
        level = 0usize
        while level < levels {
            let index = offset + level
            if storage.counts[index] == 0usize || !finite64(storage.means[index]) { ret (zero, Invalid) }
            let mean = values[0usize] + storage.means[index] / f64(storage.counts[index])
            if !finite64(mean) { ret (zero, Invalid) }
            storage.means[index] = mean
            let point = Coord { x: left + panel_width * (f32(level) + 0.5) / f32(levels), y: bounds.y + bounds.height * f32((hi - mean) / (hi - lo)) }
            if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
            storage.points[index] = point
            if level > 0usize {
                storage.lines[line] = Segment { from: storage.points[index - 1usize], to: point }
                line += 1usize
            }
            level += 1usize
        }
        offset += levels
        factor += 1usize
    }
    let marks = Layout { kind: .Scatter, coords: storage.points[..total_levels], segments: zero, bars: zero, x_min: 0.0, x_max: f32(total_levels), y_min: f32(lo), y_max: f32(hi) }
    let joins = Layout { kind: .Rug, coords: zero, segments: storage.lines[..connections], bars: zero, x_min: 0.0, x_max: f32(total_levels), y_min: f32(lo), y_max: f32(hi) }
    let references = Layout { kind: .Rug, coords: zero, segments: storage.references[..factor_levels.len], bars: zero, x_min: 0.0, x_max: f32(total_levels), y_min: f32(lo), y_max: f32(hi) }
    ret (MainEffectsLayout { levels: marks, connections: joins, reference: references, means: storage.means[..total_levels], counts: storage.counts[..total_levels], grand_mean: grand_mean }, ok)
}

// One-way analysis of means. The caller supplies the ANOM critical h for its
// chosen familywise alpha, group count and error degrees of freedom. This
// keeps exact/table criticals distinct from ordinary normal quantiles. Unequal
// group sizes get independent decision limits; the variance is pooled within
// groups, not across their different means.
fn anom(values: []const f64, group_ids: []const usize, groups: usize, critical: f64, bounds: geometry.Rect, storage: *AnomStorage) -> (AnomLayout, err) {
    if values.len == 0usize || values.len != group_ids.len || groups < 2usize || values.len <= groups || !finite64(critical) || critical <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if storage.points.len < groups || storage.signals.len < groups || storage.upper.len < groups || storage.lower.len < groups || storage.center.len < 1usize || storage.means.len < groups || storage.counts.len < groups || storage.upper_limits.len < groups || storage.lower_limits.len < groups { ret (zero, TooLarge) }
    var group = 0usize
    while group < groups {
        storage.means[group] = 0.0f64
        storage.counts[group] = 0usize
        group += 1usize
    }
    let baseline = values[0usize]
    var total = 0.0f64
    var row = 0usize
    while row < values.len {
        let value = values[row]
        let id = group_ids[row]
        if !finite64(value) || id >= groups { ret (zero, Invalid) }
        let centered = value - baseline
        if !finite64(centered) { ret (zero, Invalid) }
        total += centered
        storage.means[id] += centered
        storage.counts[id] += 1usize
        row += 1usize
    }
    let grand_mean = baseline + total / f64(values.len)
    if !finite64(total) || !finite64(grand_mean) { ret (zero, Invalid) }
    group = 0usize
    while group < groups {
        if storage.counts[group] == 0usize || !finite64(storage.means[group]) { ret (zero, Invalid) }
        storage.means[group] = baseline + storage.means[group] / f64(storage.counts[group])
        if !finite64(storage.means[group]) { ret (zero, Invalid) }
        group += 1usize
    }
    var squared_error = 0.0f64
    row = 0usize
    while row < values.len {
        let residual = values[row] - storage.means[group_ids[row]]
        squared_error += residual * residual
        row += 1usize
    }
    let pooled_sd = math.sqrt[f64](squared_error / f64(values.len - groups))
    if !finite64(pooled_sd) { ret (zero, Invalid) }
    var lo = grand_mean
    var hi = grand_mean
    group = 0usize
    while group < groups {
        let n = f64(storage.counts[group])
        let standard_error = pooled_sd * math.sqrt[f64]((f64(values.len) - n) / (f64(values.len) * n))
        let offset = critical * standard_error
        storage.lower_limits[group] = grand_mean - offset
        storage.upper_limits[group] = grand_mean + offset
        if !finite64(storage.lower_limits[group]) || !finite64(storage.upper_limits[group]) { ret (zero, Invalid) }
        lo = math.min[f64](lo, math.min[f64](storage.means[group], storage.lower_limits[group]))
        hi = math.max[f64](hi, math.max[f64](storage.means[group], storage.upper_limits[group]))
        group += 1usize
    }
    let pad = math.max[f64](1.0f64, (hi - lo) * 0.08f64)
    lo -= pad
    hi += pad
    if !finite64(lo) || !finite64(hi) || !finite64(hi - lo) || !finite(f32(lo)) || !finite(f32(hi)) { ret (zero, Invalid) }
    let cell = bounds.width / f32(groups)
    var signals = 0usize
    group = 0usize
    while group < groups {
        let x0 = bounds.x + cell * f32(group)
        let x1 = x0 + cell
        let x = x0 + cell * 0.5
        let mean_y = bounds.y + bounds.height * f32((hi - storage.means[group]) / (hi - lo))
        let lower_y = bounds.y + bounds.height * f32((hi - storage.lower_limits[group]) / (hi - lo))
        let upper_y = bounds.y + bounds.height * f32((hi - storage.upper_limits[group]) / (hi - lo))
        if !finite(x) || !finite(mean_y) || !finite(lower_y) || !finite(upper_y) { ret (zero, Invalid) }
        storage.points[group] = Coord { x: x, y: mean_y }
        if storage.means[group] < storage.lower_limits[group] || storage.means[group] > storage.upper_limits[group] {
            storage.signals[signals] = storage.points[group]
            signals += 1usize
        }
        storage.lower[group] = Segment { from: Coord { x: x0, y: lower_y }, to: Coord { x: x1, y: lower_y } }
        storage.upper[group] = Segment { from: Coord { x: x0, y: upper_y }, to: Coord { x: x1, y: upper_y } }
        group += 1usize
    }
    let center_y = bounds.y + bounds.height * f32((hi - grand_mean) / (hi - lo))
    storage.center[0usize] = Segment { from: Coord { x: bounds.x, y: center_y }, to: Coord { x: bounds.x + bounds.width, y: center_y } }
    let points = Layout { kind: .Scatter, coords: storage.points[..groups], segments: zero, bars: zero, x_min: 0.0, x_max: f32(groups), y_min: f32(lo), y_max: f32(hi) }
    let flags = Layout { kind: .Scatter, coords: storage.signals[..signals], segments: zero, bars: zero, x_min: 0.0, x_max: f32(groups), y_min: f32(lo), y_max: f32(hi) }
    let udl = Layout { kind: .Rug, coords: zero, segments: storage.upper[..groups], bars: zero, x_min: 0.0, x_max: f32(groups), y_min: f32(lo), y_max: f32(hi) }
    let ldl = Layout { kind: .Rug, coords: zero, segments: storage.lower[..groups], bars: zero, x_min: 0.0, x_max: f32(groups), y_min: f32(lo), y_max: f32(hi) }
    let mid = Layout { kind: .Rug, coords: zero, segments: storage.center[..1usize], bars: zero, x_min: 0.0, x_max: f32(groups), y_min: f32(lo), y_max: f32(hi) }
    ret (AnomLayout { groups: points, signals: flags, upper: udl, lower: ldl, center: mid, means: storage.means[..groups], counts: storage.counts[..groups], upper_limits: storage.upper_limits[..groups], lower_limits: storage.lower_limits[..groups], grand_mean: grand_mean, pooled_sd: pooled_sd, critical: critical }, ok)
}

// Individual-observation Hotelling T-squared chart. Empty historical data
// gives Phase I (baseline and monitored rows coincide); nonempty historical
// data gives Phase II. The reference mean/covariance are estimated only from
// baseline rows, and the phase-specific upper limit uses the beta/F result.
// There is no lower control limit for this first monitoring surface.
fn hotelling_t2_individuals(values: []const f64, columns: usize, historical: []const f64, alpha: f64, bounds: geometry.Rect, storage: *HotellingStorage) -> (HotellingLayout, err) {
    if columns < 2usize || values.len == 0usize || values.len % columns != 0usize || historical.len % columns != 0usize || !finite64(alpha) || alpha <= 0.0f64 || alpha >= 1.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    var baseline = values
    let phase_two = historical.len != 0usize
    if phase_two { baseline = historical }
    let monitored = values.len / columns
    let m = baseline.len / columns
    if m <= columns + 1usize { ret (zero, Invalid) }
    if storage.means.len < columns || storage.covariance.len < columns * columns || storage.factor.len < columns * columns || storage.residual.len < columns || storage.scores.len < monitored || storage.points.len < monitored || storage.segments.len < monitored - 1usize || storage.signals.len < monitored || storage.upper.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < baseline.len {
        if !finite64(baseline[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var j = 0usize
    while j < columns {
        let origin = baseline[j]
        var total = 0.0f64
        i = 0usize
        while i < m {
            total += baseline[i * columns + j] - origin
            i += 1usize
        }
        storage.means[j] = origin + total / f64(m)
        if !finite64(storage.means[j]) { ret (zero, Invalid) }
        j += 1usize
    }
    if stat.covariance_matrix(baseline, columns, storage.covariance[..columns * columns]) != ok { ret (zero, Invalid) }
    i = 0usize
    while i < columns * columns {
        if !finite64(storage.covariance[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    if filter.cholesky(storage.covariance[..columns * columns], columns, storage.factor[..columns * columns]) != ok { ret (zero, Invalid) }
    let p = f64(columns)
    let size = f64(m)
    var upper_limit = 0.0f64
    if phase_two {
        let beta = stat.beta_quantile(1.0f64 - alpha / 2.0f64, p / 2.0f64, (size - p) / 2.0f64)
        if beta >= 1.0f64 { ret (zero, Invalid) }
        upper_limit = ((size + 1.0f64) * (size - 1.0f64) / size) * beta / (1.0f64 - beta)
    } else {
        let beta = stat.beta_quantile(1.0f64 - alpha / 2.0f64, p / 2.0f64, (size - p - 1.0f64) / 2.0f64)
        upper_limit = ((size - 1.0f64) * (size - 1.0f64) / size) * beta
    }
    if !finite64(upper_limit) || upper_limit <= 0.0f64 { ret (zero, Invalid) }
    var highest = upper_limit
    var flags = 0usize
    i = 0usize
    while i < monitored {
        j = 0usize
        while j < columns {
            storage.residual[j] = values[i * columns + j] - storage.means[j]
            if !finite64(storage.residual[j]) { ret (zero, Invalid) }
            j += 1usize
        }
        var score = 0.0f64
        j = 0usize
        while j < columns {
            var component = storage.residual[j]
            var k = 0usize
            while k < j {
                component -= storage.factor[j * columns + k] * storage.residual[k]
                k += 1usize
            }
            component /= storage.factor[j * columns + j]
            storage.residual[j] = component
            score += component * component
            j += 1usize
        }
        if !finite64(score) || score < 0.0f64 { ret (zero, Invalid) }
        storage.scores[i] = score
        highest = math.max[f64](highest, score)
        i += 1usize
    }
    let top = highest * 1.1f64
    if !finite64(top) || !finite(f32(top)) { ret (zero, Invalid) }
    i = 0usize
    while i < monitored {
        let x = bounds.x + bounds.width * (f32(i) + 0.5) / f32(monitored)
        let y = bounds.y + bounds.height * f32(1.0f64 - storage.scores[i] / top)
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        let point = Coord { x: x, y: y }
        storage.points[i] = point
        if i > 0usize { storage.segments[i - 1usize] = Segment { from: storage.points[i - 1usize], to: point } }
        if storage.scores[i] > upper_limit {
            storage.signals[flags] = point
            flags += 1usize
        }
        i += 1usize
    }
    let upper_y = bounds.y + bounds.height * f32(1.0f64 - upper_limit / top)
    storage.upper[0usize] = Segment { from: Coord { x: bounds.x, y: upper_y }, to: Coord { x: bounds.x + bounds.width, y: upper_y } }
    let trace = Layout { kind: .PointLine, coords: storage.points[..monitored], segments: storage.segments[..monitored - 1usize], bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    let signals = Layout { kind: .Scatter, coords: storage.signals[..flags], segments: zero, bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    let upper = Layout { kind: .Rug, coords: zero, segments: storage.upper[..1usize], bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    ret (HotellingLayout { trace: trace, signals: signals, upper: upper, means: storage.means[..columns], covariance: storage.covariance[..columns * columns], scores: storage.scores[..monitored], upper_limit: upper_limit, historical_count: m, phase_two: phase_two }, ok)
}

// Generalized-variance |S| chart for equal-size multivariate subgroups.
// Phase I estimates the reference covariance; optional Phase II subgroups do
// not change it. Limits are the moment-normal approximation, not exact tail
// quantiles. A one-sided chart has LCL 0; two-sided uses alpha/2 per tail.
fn generalized_variance(phase_one: []const f64, phase_two: []const f64, subgroup_size: usize, columns: usize, alpha: f64, two_sided: bool, bounds: geometry.Rect, storage: *GeneralizedVarianceStorage) -> (GeneralizedVarianceLayout, err) {
    if columns < 2usize || subgroup_size <= columns || phase_one.len == 0usize || !finite64(alpha) || alpha <= 0.0f64 || alpha >= 1.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if phase_one.len % columns != 0usize || phase_two.len % columns != 0usize { ret (zero, Invalid) }
    let phase_one_rows = phase_one.len / columns
    let phase_two_rows = phase_two.len / columns
    if phase_one_rows % subgroup_size != 0usize || phase_two_rows % subgroup_size != 0usize { ret (zero, Invalid) }
    let first_count = phase_one_rows / subgroup_size
    let second_count = phase_two_rows / subgroup_size
    if first_count < 2usize { ret (zero, Invalid) }
    let count = first_count + second_count
    if storage.covariance.len < columns * columns || storage.pooled.len < columns * columns || storage.factor.len < columns * columns || storage.determinants.len < count || storage.points.len < count || storage.segments.len < count - 1usize || storage.signals.len < count || storage.upper.len < 1usize || storage.lower.len < 1usize || storage.center.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < phase_one.len {
        if !finite64(phase_one[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < phase_two.len {
        if !finite64(phase_two[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < columns * columns {
        storage.pooled[i] = 0.0f64
        i += 1usize
    }
    var highest = 0.0f64
    var group = 0usize
    while group < count {
        var source = phase_one
        var local_group = group
        if group >= first_count {
            source = phase_two
            local_group = group - first_count
        }
        let start = local_group * subgroup_size * columns
        let sample = source[start..start + subgroup_size * columns]
        if stat.covariance_matrix(sample, columns, storage.covariance[..columns * columns]) != ok { ret (zero, Invalid) }
        i = 0usize
        while i < columns * columns {
            if !finite64(storage.covariance[i]) { ret (zero, Invalid) }
            if group < first_count { storage.pooled[i] += storage.covariance[i] / f64(first_count) }
            i += 1usize
        }
        var determinant = 0.0f64
        if filter.cholesky(storage.covariance[..columns * columns], columns, storage.factor[..columns * columns]) == ok {
            determinant = 1.0f64
            i = 0usize
            while i < columns {
                let diagonal = storage.factor[i * columns + i]
                determinant *= diagonal * diagonal
                i += 1usize
            }
        }
        if !finite64(determinant) || determinant < 0.0f64 { ret (zero, Invalid) }
        storage.determinants[group] = determinant
        highest = math.max[f64](highest, determinant)
        group += 1usize
    }
    i = 0usize
    while i < columns * columns {
        if !finite64(storage.pooled[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    if filter.cholesky(storage.pooled[..columns * columns], columns, storage.factor[..columns * columns]) != ok { ret (zero, Invalid) }
    var pooled_det = 1.0f64
    i = 0usize
    while i < columns {
        let diagonal = storage.factor[i * columns + i]
        pooled_det *= diagonal * diagonal
        i += 1usize
    }
    let n = f64(subgroup_size)
    let df = n - 1.0f64
    let pooled_df = f64(first_count) * df
    var b1 = 1.0f64
    var second_moment = 1.0f64
    var b3 = 1.0f64
    i = 0usize
    while i < columns {
        let j = f64(i + 1usize)
        let term = n - j
        b1 *= term / df
        second_moment *= term * (term + 2.0f64) / (df * df)
        b3 *= (pooled_df - f64(i)) / pooled_df
        i += 1usize
    }
    var b2 = second_moment - b1 * b1
    if b2 < 0.0f64 && b2 > -1.0e-12f64 { b2 = 0.0f64 }
    if !finite64(pooled_det) || pooled_det <= 0.0f64 || !finite64(b1) || !finite64(b2) || !finite64(b3) || b2 < 0.0f64 || b3 <= 0.0f64 { ret (zero, Invalid) }
    let det_sigma = pooled_det / b3
    var tail = alpha
    if two_sided { tail = alpha / 2.0f64 }
    let z = special.normal_quantile(1.0f64 - tail)
    let center_value = b1 * det_sigma
    let spread = z * math.sqrt[f64](b2) * det_sigma
    let upper_limit = center_value + spread
    var lower_limit = 0.0f64
    if two_sided { lower_limit = math.max[f64](0.0f64, center_value - spread) }
    if !finite64(center_value) || !finite64(upper_limit) || !finite64(lower_limit) || upper_limit <= 0.0f64 { ret (zero, Invalid) }
    highest = math.max[f64](highest, upper_limit)
    let top = highest * 1.1f64
    if !finite64(top) || !finite(f32(top)) { ret (zero, Invalid) }
    var flags = 0usize
    group = 0usize
    while group < count {
        let point = Coord { x: bounds.x + bounds.width * (f32(group) + 0.5) / f32(count), y: bounds.y + bounds.height * f32(1.0f64 - storage.determinants[group] / top) }
        if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
        storage.points[group] = point
        if group > 0usize { storage.segments[group - 1usize] = Segment { from: storage.points[group - 1usize], to: point } }
        if storage.determinants[group] > upper_limit || storage.determinants[group] < lower_limit {
            storage.signals[flags] = point
            flags += 1usize
        }
        group += 1usize
    }
    let center_y = bounds.y + bounds.height * f32(1.0f64 - center_value / top)
    let upper_y = bounds.y + bounds.height * f32(1.0f64 - upper_limit / top)
    let lower_y = bounds.y + bounds.height * f32(1.0f64 - lower_limit / top)
    let left = bounds.x
    let right = bounds.x + bounds.width
    storage.center[0usize] = Segment { from: Coord { x: left, y: center_y }, to: Coord { x: right, y: center_y } }
    storage.upper[0usize] = Segment { from: Coord { x: left, y: upper_y }, to: Coord { x: right, y: upper_y } }
    storage.lower[0usize] = Segment { from: Coord { x: left, y: lower_y }, to: Coord { x: right, y: lower_y } }
    let trace = Layout { kind: .PointLine, coords: storage.points[..count], segments: storage.segments[..count - 1usize], bars: zero, x_min: 0.0, x_max: f32(count), y_min: 0.0, y_max: f32(top) }
    let signals = Layout { kind: .Scatter, coords: storage.signals[..flags], segments: zero, bars: zero, x_min: 0.0, x_max: f32(count), y_min: 0.0, y_max: f32(top) }
    let upper = Layout { kind: .Rug, coords: zero, segments: storage.upper[..1usize], bars: zero, x_min: 0.0, x_max: f32(count), y_min: 0.0, y_max: f32(top) }
    let lower = Layout { kind: .Rug, coords: zero, segments: storage.lower[..1usize], bars: zero, x_min: 0.0, x_max: f32(count), y_min: 0.0, y_max: f32(top) }
    let center = Layout { kind: .Rug, coords: zero, segments: storage.center[..1usize], bars: zero, x_min: 0.0, x_max: f32(count), y_min: 0.0, y_max: f32(top) }
    ret (GeneralizedVarianceLayout { trace: trace, signals: signals, upper: upper, lower: lower, center: center, determinants: storage.determinants[..count], pooled_covariance: storage.pooled[..columns * columns], center_value: center_value, lower_limit: lower_limit, upper_limit: upper_limit, b1: b1, b2: b2, b3: b3, phase_one_count: first_count, phase_two_count: second_count }, ok)
}

// Multivariate EWMA for individual observations with a shared smoothing
// coefficient. The caller supplies an ARL-calibrated UCL; the finite-time
// covariance factor is exact under the fixed-reference model. Historical rows
// estimate the mean/covariance for Phase II, or empty historical data makes a
// retrospective Phase I chart from the plotted observations.
fn mewma(values: []const f64, columns: usize, historical: []const f64, lambda: f64, upper_limit: f64, bounds: geometry.Rect, storage: *MewmaStorage) -> (MewmaLayout, err) {
    if columns < 2usize || values.len == 0usize || values.len % columns != 0usize || historical.len % columns != 0usize || !finite64(lambda) || lambda <= 0.0f64 || lambda > 1.0f64 || !finite64(upper_limit) || upper_limit <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    var baseline = values
    let phase_two = historical.len != 0usize
    if phase_two { baseline = historical }
    let monitored = values.len / columns
    let m = baseline.len / columns
    if m <= columns + 1usize { ret (zero, Invalid) }
    if storage.means.len < columns || storage.covariance.len < columns * columns || storage.factor.len < columns * columns || storage.state.len < columns || storage.residual.len < columns || storage.smoothed.len < values.len || storage.scores.len < monitored || storage.points.len < monitored || storage.segments.len < monitored - 1usize || storage.signals.len < monitored || storage.upper.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < baseline.len {
        if !finite64(baseline[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var j = 0usize
    while j < columns {
        let origin = baseline[j]
        var total = 0.0f64
        i = 0usize
        while i < m {
            total += baseline[i * columns + j] - origin
            i += 1usize
        }
        storage.means[j] = origin + total / f64(m)
        storage.state[j] = 0.0f64
        if !finite64(storage.means[j]) { ret (zero, Invalid) }
        j += 1usize
    }
    if stat.covariance_matrix(baseline, columns, storage.covariance[..columns * columns]) != ok { ret (zero, Invalid) }
    i = 0usize
    while i < columns * columns {
        if !finite64(storage.covariance[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    if filter.cholesky(storage.covariance[..columns * columns], columns, storage.factor[..columns * columns]) != ok { ret (zero, Invalid) }
    let decay = 1.0f64 - lambda
    var decay_power = 1.0f64
    var highest = upper_limit
    i = 0usize
    while i < monitored {
        decay_power *= decay * decay
        let covariance_factor = lambda / (2.0f64 - lambda) * (1.0f64 - decay_power)
        if !finite64(covariance_factor) || covariance_factor <= 0.0f64 { ret (zero, Invalid) }
        j = 0usize
        while j < columns {
            storage.state[j] = decay * storage.state[j] + lambda * (values[i * columns + j] - storage.means[j])
            storage.smoothed[i * columns + j] = storage.means[j] + storage.state[j]
            storage.residual[j] = storage.state[j]
            if !finite64(storage.state[j]) || !finite64(storage.smoothed[i * columns + j]) { ret (zero, Invalid) }
            j += 1usize
        }
        var quadratic = 0.0f64
        j = 0usize
        while j < columns {
            var component = storage.residual[j]
            var k = 0usize
            while k < j {
                component -= storage.factor[j * columns + k] * storage.residual[k]
                k += 1usize
            }
            component /= storage.factor[j * columns + j]
            storage.residual[j] = component
            quadratic += component * component
            j += 1usize
        }
        let score = quadratic / covariance_factor
        if !finite64(score) || score < 0.0f64 { ret (zero, Invalid) }
        storage.scores[i] = score
        highest = math.max[f64](highest, score)
        i += 1usize
    }
    let top = highest * 1.1f64
    if !finite64(top) || !finite(f32(top)) { ret (zero, Invalid) }
    var flags = 0usize
    i = 0usize
    while i < monitored {
        let point = Coord { x: bounds.x + bounds.width * (f32(i) + 0.5) / f32(monitored), y: bounds.y + bounds.height * f32(1.0f64 - storage.scores[i] / top) }
        if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
        storage.points[i] = point
        if i > 0usize { storage.segments[i - 1usize] = Segment { from: storage.points[i - 1usize], to: point } }
        if storage.scores[i] > upper_limit {
            storage.signals[flags] = point
            flags += 1usize
        }
        i += 1usize
    }
    let upper_y = bounds.y + bounds.height * f32(1.0f64 - upper_limit / top)
    storage.upper[0usize] = Segment { from: Coord { x: bounds.x, y: upper_y }, to: Coord { x: bounds.x + bounds.width, y: upper_y } }
    let trace = Layout { kind: .PointLine, coords: storage.points[..monitored], segments: storage.segments[..monitored - 1usize], bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    let signals = Layout { kind: .Scatter, coords: storage.signals[..flags], segments: zero, bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    let upper = Layout { kind: .Rug, coords: zero, segments: storage.upper[..1usize], bars: zero, x_min: 0.0, x_max: f32(monitored), y_min: 0.0, y_max: f32(top) }
    ret (MewmaLayout { trace: trace, signals: signals, upper: upper, means: storage.means[..columns], covariance: storage.covariance[..columns * columns], smoothed: storage.smoothed[..values.len], scores: storage.scores[..monitored], upper_limit: upper_limit, lambda: lambda, historical_count: m, phase_two: phase_two }, ok)
}

// Two-factor raw-means interaction plot. Cell order is series-major, then
// x-level. Series remain separate PointLine layers for independent styling.
fn interaction_plot(values: []const f64, x_ids: []const usize, series_ids: []const usize, x_levels: usize, series_levels: usize, bounds: geometry.Rect, storage: *InteractionStorage) -> (InteractionLayout, err) {
    if values.len == 0usize || x_levels < 2usize || series_levels < 2usize || x_ids.len != values.len || series_ids.len != values.len || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if x_levels > values.len || series_levels > values.len || series_levels > values.len / x_levels { ret (zero, Invalid) }
    let cells = x_levels * series_levels
    if storage.points.len < cells || storage.lines.len < series_levels * (x_levels - 1usize) || storage.means.len < cells || storage.counts.len < cells || storage.series.len < series_levels { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = values[0usize]
    var row = 0usize
    while row < values.len {
        if !finite64(values[row]) || x_ids[row] >= x_levels || series_ids[row] >= series_levels { ret (zero, Invalid) }
        if values[row] < lo { lo = values[row] }
        if values[row] > hi { hi = values[row] }
        row += 1usize
    }
    if lo == hi {
        let pad = math.max[f64](1.0f64, math.abs[f64](lo) * 0.05f64)
        lo -= pad
        hi += pad
    }
    if !finite64(lo) || !finite64(hi) || !finite64(hi - lo) || hi <= lo || !finite(f32(lo)) || !finite(f32(hi)) { ret (zero, Invalid) }
    var cell = 0usize
    while cell < cells {
        storage.means[cell] = 0.0f64
        storage.counts[cell] = 0usize
        cell += 1usize
    }
    row = 0usize
    while row < values.len {
        let index = series_ids[row] * x_levels + x_ids[row]
        storage.means[index] += values[row] - values[0usize]
        storage.counts[index] += 1usize
        row += 1usize
    }
    var series = 0usize
    while series < series_levels {
        var level = 0usize
        while level < x_levels {
            let index = series * x_levels + level
            if storage.counts[index] == 0usize || !finite64(storage.means[index]) { ret (zero, Invalid) }
            let mean = values[0usize] + storage.means[index] / f64(storage.counts[index])
            if !finite64(mean) { ret (zero, Invalid) }
            storage.means[index] = mean
            let point = Coord { x: bounds.x + bounds.width * (f32(level) + 0.5) / f32(x_levels), y: bounds.y + bounds.height * f32((hi - mean) / (hi - lo)) }
            if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
            storage.points[index] = point
            if level > 0usize { storage.lines[series * (x_levels - 1usize) + level - 1usize] = Segment { from: storage.points[index - 1usize], to: point } }
            level += 1usize
        }
        storage.series[series] = Layout { kind: .PointLine, coords: storage.points[series * x_levels..(series + 1usize) * x_levels], segments: storage.lines[series * (x_levels - 1usize)..(series + 1usize) * (x_levels - 1usize)], bars: zero, x_min: 0.0, x_max: f32(x_levels), y_min: f32(lo), y_max: f32(hi) }
        series += 1usize
    }
    ret (InteractionLayout { series: storage.series[..series_levels], means: storage.means[..cells], counts: storage.counts[..cells] }, ok)
}

// Three two-level factors: ids are observation-major triples; bits of each
// vertex index encode factor A, B and C. The projected cube geometry is
// response-independent, while numeric raw cell means stay caller-owned.
fn cube_plot(values: []const f64, factor_ids: []const usize, bounds: geometry.Rect, storage: *CubePlotStorage) -> (CubePlotLayout, err) {
    if values.len < 8usize || values.len > factor_ids.len / 3usize || factor_ids.len != values.len * 3usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if storage.vertices.len < 8usize || storage.edges.len < 12usize || storage.means.len < 8usize || storage.counts.len < 8usize { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = values[0usize]
    var row = 0usize
    while row < values.len {
        if !finite64(values[row]) || factor_ids[row * 3usize] > 1usize || factor_ids[row * 3usize + 1usize] > 1usize || factor_ids[row * 3usize + 2usize] > 1usize { ret (zero, Invalid) }
        if values[row] < lo { lo = values[row] }
        if values[row] > hi { hi = values[row] }
        row += 1usize
    }
    if lo == hi {
        let pad = math.max[f64](1.0f64, math.abs[f64](lo) * 0.05f64)
        lo -= pad
        hi += pad
    }
    if !finite64(lo) || !finite64(hi) || !finite64(hi - lo) || hi <= lo || !finite(f32(lo)) || !finite(f32(hi)) { ret (zero, Invalid) }
    var vertex = 0usize
    while vertex < 8usize {
        storage.means[vertex] = 0.0f64
        storage.counts[vertex] = 0usize
        let x = f32(vertex % 2usize)
        let y = f32((vertex / 2usize) % 2usize)
        let z = f32(vertex / 4usize)
        let point = Coord { x: bounds.x + bounds.width * (0.16 + 0.58 * x + 0.18 * z), y: bounds.y + bounds.height * (0.88 - 0.58 * y - 0.18 * z) }
        if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
        storage.vertices[vertex] = point
        vertex += 1usize
    }
    row = 0usize
    while row < values.len {
        let index = factor_ids[row * 3usize] + factor_ids[row * 3usize + 1usize] * 2usize + factor_ids[row * 3usize + 2usize] * 4usize
        storage.means[index] += values[row] - values[0usize]
        storage.counts[index] += 1usize
        row += 1usize
    }
    vertex = 0usize
    var edge = 0usize
    while vertex < 8usize {
        if storage.counts[vertex] == 0usize || !finite64(storage.means[vertex]) { ret (zero, Invalid) }
        let mean = values[0usize] + storage.means[vertex] / f64(storage.counts[vertex])
        if !finite64(mean) { ret (zero, Invalid) }
        storage.means[vertex] = mean
        if vertex % 2usize == 0usize {
            storage.edges[edge] = Segment { from: storage.vertices[vertex], to: storage.vertices[vertex + 1usize] }
            edge += 1usize
        }
        if (vertex / 2usize) % 2usize == 0usize {
            storage.edges[edge] = Segment { from: storage.vertices[vertex], to: storage.vertices[vertex + 2usize] }
            edge += 1usize
        }
        if vertex < 4usize {
            storage.edges[edge] = Segment { from: storage.vertices[vertex], to: storage.vertices[vertex + 4usize] }
            edge += 1usize
        }
        vertex += 1usize
    }
    let corners = Layout { kind: .Scatter, coords: storage.vertices[..8usize], segments: zero, bars: zero, x_min: 0.0, x_max: 2.0, y_min: f32(lo), y_max: f32(hi) }
    let wireframe = Layout { kind: .Rug, coords: zero, segments: storage.edges[..12usize], bars: zero, x_min: 0.0, x_max: 2.0, y_min: f32(lo), y_max: f32(hi) }
    ret (CubePlotLayout { vertices: corners, frame: wireframe, means: storage.means[..8usize], counts: storage.counts[..8usize] }, ok)
}

// One-sided STFT power in dB relative to unit power, with a caller-selected
// positive floor. `re` and `im` are frame-major FFT outputs from e.dsp.stft;
// the lowest frequency occupies the bottom heatmap row.
fn spectrogram(re: []const f64, im: []const f64, frames: usize, fft_size: usize, hop: usize, sample_rate: f64, floor_power: f64, bounds: geometry.Rect, cells: []Cell) -> (SpectrogramLayout, err) {
    if frames == 0usize || fft_size < 2usize || hop == 0usize || !finite64(sample_rate) || sample_rate <= 0.0f64 || !finite64(floor_power) || floor_power <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if frames > re.len / fft_size || re.len != frames * fft_size || im.len != re.len { ret (zero, Invalid) }
    let rows = fft_size / 2usize + 1usize
    if frames > cells.len / rows { ret (zero, TooLarge) }
    let time_start = f64(fft_size) * 0.5f64 / sample_rate
    let time_end = (f64(frames - 1usize) * f64(hop) + f64(fft_size) * 0.5f64) / sample_rate
    let frequency_max = sample_rate * 0.5f64
    if !finite64(time_start) || !finite64(time_end) || !finite64(frequency_max) { ret (zero, Invalid) }
    var lo = 0.0f32
    var hi = 0.0f32
    var index = 0usize
    var row = 0usize
    while row < rows {
        let bin = rows - row - 1usize
        var frame = 0usize
        while frame < frames {
            let input = frame * fft_size + bin
            let real = re[input]
            let imag = im[input]
            if !finite64(real) || !finite64(imag) { ret (zero, Invalid) }
            let power = real * real + imag * imag
            if !finite64(power) { ret (zero, Invalid) }
            let db = 10.0f64 * math.log10[f64](math.max[f64](power, floor_power))
            if !finite64(db) || !finite(f32(db)) { ret (zero, Invalid) }
            let value = f32(db)
            cells[index] = Cell { rect: cell_rect(bounds, frame, row, frames, rows), value: value }
            if index == 0usize || value < lo { lo = value }
            if index == 0usize || value > hi { hi = value }
            index += 1usize
            frame += 1usize
        }
        row += 1usize
    }
    let matrix = MatrixLayout { kind: .Heatmap, cells: cells[..frames * rows], columns: frames, rows: rows, value_min: lo, value_max: hi }
    ret (SpectrogramLayout { matrix: matrix, time_start: time_start, time_end: time_end, frequency_max: frequency_max }, ok)
}

// Oblique frequency traces sampled from an existing one-sided spectrogram.
// The matrix remains in screen row order (high frequency first), while each
// returned trace runs from low to high frequency without joining time slices.
fn waterfall_spectrum(spectrum: *const SpectrogramLayout, frame_step: usize, bounds: geometry.Rect, storage: *WaterfallSpectrumStorage) -> (WaterfallSpectrumLayout, err) {
    let matrix = spectrum.matrix
    let frames = matrix.columns
    let bins = matrix.rows
    if matrix.kind != .Heatmap || frames < 2usize || bins < 2usize || frame_step == 0usize || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if frames > matrix.cells.len / bins || matrix.cells.len != frames * bins { ret (zero, Invalid) }
    let trace_count = (frames - 1usize) / frame_step + 1usize
    if trace_count < 2usize { ret (zero, Invalid) }
    if trace_count > storage.points.len / bins || trace_count > storage.segments.len / (bins - 1usize) || storage.traces.len < trace_count || storage.frame_indices.len < trace_count { ret (zero, TooLarge) }
    var lo = matrix.cells[0usize].value
    var hi = lo
    var i = 0usize
    while i < matrix.cells.len {
        let value = matrix.cells[i].value
        if !finite(value) { ret (zero, Invalid) }
        if value < lo { lo = value }
        if value > hi { hi = value }
        i += 1usize
    }
    if !finite(hi - lo) { ret (zero, Invalid) }
    var trace = 0usize
    while trace < trace_count {
        let frame = trace * frame_step
        let depth = f32(trace) / f32(trace_count - 1usize)
        let left = bounds.x + bounds.width * (0.09 + 0.18 * depth)
        let base = bounds.y + bounds.height * (0.88 - 0.38 * depth)
        var bin = 0usize
        while bin < bins {
            let value = matrix.cells[(bins - 1usize - bin) * frames + frame].value
            var amplitude = 0.0f32
            if hi > lo { amplitude = (value - lo) / (hi - lo) }
            let point = Coord { x: left + bounds.width * 0.68 * f32(bin) / f32(bins - 1usize), y: base - bounds.height * 0.32 * amplitude }
            if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
            let index = trace * bins + bin
            storage.points[index] = point
            if bin > 0usize { storage.segments[trace * (bins - 1usize) + bin - 1usize] = Segment { from: storage.points[index - 1usize], to: point } }
            bin += 1usize
        }
        storage.frame_indices[trace] = frame
        storage.traces[trace] = Layout { kind: .Line, coords: storage.points[trace * bins..(trace + 1usize) * bins], segments: storage.segments[trace * (bins - 1usize)..(trace + 1usize) * (bins - 1usize)], bars: zero, x_min: 0.0, x_max: f32(bins - 1usize), y_min: lo, y_max: hi }
        trace += 1usize
    }
    ret (WaterfallSpectrumLayout { traces: storage.traces[..trace_count], frame_indices: storage.frame_indices[..trace_count], value_min: lo, value_max: hi }, ok)
}

// Bode geometry for sampled complex frequency response. Frequencies must be
// strictly increasing and positive; phase is unwrapped across ±180 degrees.
fn bode(frequency: []const f64, real: []const f64, imag: []const f64, magnitude_floor: f64, bounds: geometry.Rect, storage: *BodeStorage) -> (BodeLayout, err) {
    if frequency.len < 2usize || frequency.len != real.len || frequency.len != imag.len || !finite64(magnitude_floor) || magnitude_floor <= 0.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    let n = frequency.len
    if storage.magnitude_points.len < n || storage.magnitude_segments.len < n - 1usize || storage.phase_points.len < n || storage.phase_segments.len < n - 1usize || storage.magnitude_db.len < n || storage.phase_degrees.len < n { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        if !finite64(frequency[i]) || frequency[i] <= 0.0f64 || !finite64(real[i]) || !finite64(imag[i]) { ret (zero, Invalid) }
        if i > 0usize && frequency[i] <= frequency[i - 1usize] { ret (zero, Invalid) }
        i += 1usize
    }
    let log_lo = math.log10[f64](frequency[0usize])
    let log_hi = math.log10[f64](frequency[n - 1usize])
    if !finite64(log_lo) || !finite64(log_hi) || !finite64(log_hi - log_lo) || log_hi <= log_lo { ret (zero, Invalid) }
    var mag_lo = 0.0f64
    var mag_hi = 0.0f64
    var phase_lo = 0.0f64
    var phase_hi = 0.0f64
    var previous_raw = 0.0f64
    var offset = 0.0f64
    i = 0usize
    while i < n {
        let ar = math.abs[f64](real[i])
        let ai = math.abs[f64](imag[i])
        let big = math.max[f64](ar, ai)
        var amplitude = 0.0f64
        if big > 0.0f64 {
            let small = math.min[f64](ar, ai)
            let ratio = small / big
            amplitude = big * math.sqrt[f64](1.0f64 + ratio * ratio)
        }
        if !finite64(amplitude) { ret (zero, Invalid) }
        let magnitude = 20.0f64 * math.log10[f64](math.max[f64](amplitude, magnitude_floor))
        let raw_phase = math.atan2[f64](imag[i], real[i]) * 57.29577951308232f64
        if i > 0usize {
            let delta = raw_phase - previous_raw
            if delta > 180.0f64 { offset -= 360.0f64 }
            if delta < -180.0f64 { offset += 360.0f64 }
        }
        let phase = raw_phase + offset
        if !finite64(magnitude) || !finite64(phase) { ret (zero, Invalid) }
        storage.magnitude_db[i] = magnitude
        storage.phase_degrees[i] = phase
        if i == 0usize || magnitude < mag_lo { mag_lo = magnitude }
        if i == 0usize || magnitude > mag_hi { mag_hi = magnitude }
        if i == 0usize || phase < phase_lo { phase_lo = phase }
        if i == 0usize || phase > phase_hi { phase_hi = phase }
        previous_raw = raw_phase
        i += 1usize
    }
    if mag_lo == mag_hi {
        mag_lo -= 1.0f64
        mag_hi += 1.0f64
    }
    if phase_lo == phase_hi {
        phase_lo -= 1.0f64
        phase_hi += 1.0f64
    }
    if !finite64(mag_hi - mag_lo) || !finite64(phase_hi - phase_lo) || !finite(f32(mag_lo)) || !finite(f32(mag_hi)) || !finite(f32(phase_lo)) || !finite(f32(phase_hi)) { ret (zero, Invalid) }
    let magnitude_bounds = geometry.rect(bounds.x, bounds.y, bounds.width, bounds.height * 0.40)
    let phase_bounds = geometry.rect(bounds.x, bounds.y + bounds.height * 0.54, bounds.width, bounds.height * 0.40)
    i = 0usize
    while i < n {
        let log_position = (math.log10[f64](frequency[i]) - log_lo) / (log_hi - log_lo)
        let x = bounds.x + bounds.width * f32(log_position)
        let mag_point = Coord { x: x, y: magnitude_bounds.y + magnitude_bounds.height * f32((mag_hi - storage.magnitude_db[i]) / (mag_hi - mag_lo)) }
        let phase_point = Coord { x: x, y: phase_bounds.y + phase_bounds.height * f32((phase_hi - storage.phase_degrees[i]) / (phase_hi - phase_lo)) }
        if !finite(mag_point.x) || !finite(mag_point.y) || !finite(phase_point.x) || !finite(phase_point.y) { ret (zero, Invalid) }
        storage.magnitude_points[i] = mag_point
        storage.phase_points[i] = phase_point
        if i > 0usize {
            storage.magnitude_segments[i - 1usize] = Segment { from: storage.magnitude_points[i - 1usize], to: mag_point }
            storage.phase_segments[i - 1usize] = Segment { from: storage.phase_points[i - 1usize], to: phase_point }
        }
        i += 1usize
    }
    let magnitude = Layout { kind: .Line, coords: storage.magnitude_points[..n], segments: storage.magnitude_segments[..n - 1usize], bars: zero, x_min: f32(log_lo), x_max: f32(log_hi), y_min: f32(mag_lo), y_max: f32(mag_hi) }
    let phase = Layout { kind: .Line, coords: storage.phase_points[..n], segments: storage.phase_segments[..n - 1usize], bars: zero, x_min: f32(log_lo), x_max: f32(log_hi), y_min: f32(phase_lo), y_max: f32(phase_hi) }
    ret (BodeLayout { magnitude: magnitude, phase: phase, magnitude_bounds: magnitude_bounds, phase_bounds: phase_bounds, magnitude_db: storage.magnitude_db[..n], phase_degrees: storage.phase_degrees[..n], frequency_min: frequency[0usize], frequency_max: frequency[n - 1usize] }, ok)
}

// The negative-frequency branch is the conjugate reflection of a sampled
// real-coefficient SISO response. Separate paths avoid inventing the missing
// contour arcs at zero/infinity; no stability verdict follows from samples.
fn nyquist(frequency: []const f64, real: []const f64, imag: []const f64, bounds: geometry.Rect, storage: *NyquistStorage) -> (NyquistLayout, err) {
    if frequency.len < 2usize || frequency.len != real.len || frequency.len != imag.len || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    let n = frequency.len
    if storage.positive_points.len < n || storage.positive_segments.len < n - 1usize || storage.negative_points.len < n || storage.negative_segments.len < n - 1usize || storage.critical_point.len == 0usize { ret (zero, TooLarge) }
    var real_lo = -1.0f64
    var real_hi = -1.0f64
    var imag_abs = 0.0f64
    var i = 0usize
    while i < n {
        if !finite64(frequency[i]) || frequency[i] <= 0.0f64 || !finite64(real[i]) || !finite64(imag[i]) || (i > 0usize && frequency[i] <= frequency[i - 1usize]) { ret (zero, Invalid) }
        real_lo = math.min[f64](real_lo, real[i])
        real_hi = math.max[f64](real_hi, real[i])
        imag_abs = math.max[f64](imag_abs, math.abs[f64](imag[i]))
        i += 1usize
    }
    let span_x = math.max[f64](real_hi - real_lo, 1.0f64)
    let span_y = math.max[f64](2.0f64 * imag_abs, 1.0f64)
    let scale = math.min[f64](f64(bounds.width) / (1.1f64 * span_x), f64(bounds.height) / (1.1f64 * span_y))
    let center_x = real_lo + (real_hi - real_lo) * 0.5f64
    if !finite64(scale) || scale <= 0.0f64 || !finite64(center_x) { ret (zero, Invalid) }
    let x_min = center_x - f64(bounds.width) / (2.0f64 * scale)
    let x_max = center_x + f64(bounds.width) / (2.0f64 * scale)
    let y_min = -f64(bounds.height) / (2.0f64 * scale)
    let y_max = -y_min
    if !finite(f32(x_min)) || !finite(f32(x_max)) || !finite(f32(y_min)) || !finite(f32(y_max)) { ret (zero, Invalid) }
    let mid_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let mid_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    i = 0usize
    while i < n {
        let forward = Coord { x: f32(mid_x + (real[i] - center_x) * scale), y: f32(mid_y - imag[i] * scale) }
        let reverse_index = n - 1usize - i
        let reverse = Coord { x: f32(mid_x + (real[reverse_index] - center_x) * scale), y: f32(mid_y + imag[reverse_index] * scale) }
        if !finite(forward.x) || !finite(forward.y) || !finite(reverse.x) || !finite(reverse.y) { ret (zero, Invalid) }
        storage.positive_points[i] = forward
        storage.negative_points[i] = reverse
        if i > 0usize {
            storage.positive_segments[i - 1usize] = Segment { from: storage.positive_points[i - 1usize], to: forward }
            storage.negative_segments[i - 1usize] = Segment { from: storage.negative_points[i - 1usize], to: reverse }
        }
        i += 1usize
    }
    let critical = Coord { x: f32(mid_x + (-1.0f64 - center_x) * scale), y: f32(mid_y) }
    if !finite(critical.x) || !finite(critical.y) { ret (zero, Invalid) }
    storage.critical_point[0usize] = critical
    let positive = Layout { kind: .Line, coords: storage.positive_points[..n], segments: storage.positive_segments[..n - 1usize], bars: zero, x_min: f32(x_min), x_max: f32(x_max), y_min: f32(y_min), y_max: f32(y_max) }
    let negative = Layout { kind: .Line, coords: storage.negative_points[..n], segments: storage.negative_segments[..n - 1usize], bars: zero, x_min: f32(x_min), x_max: f32(x_max), y_min: f32(y_min), y_max: f32(y_max) }
    let marker = Layout { kind: .Scatter, coords: storage.critical_point[..1usize], segments: zero, bars: zero, x_min: f32(x_min), x_max: f32(x_max), y_min: f32(y_min), y_max: f32(y_max) }
    ret (NyquistLayout { positive: positive, negative: negative, critical: marker, frequency_min: frequency[0usize], frequency_max: frequency[n - 1usize] }, ok)
}

// The camera turned by `azimuth_degrees` and raised by `elevation_degrees`
// (D2116): the azimuth wraps into [-180, 180) and the elevation stays within
// `low`..`high`, themselves within -90..90 (a surface needs 0 < elevation < 90).
fn orbit(camera: Camera3d, azimuth_degrees: f64, elevation_degrees: f64, low: f64, high: f64) -> (Camera3d, err) {
    if !finite64(camera.azimuth_degrees) || !finite64(camera.elevation_degrees) || !finite64(azimuth_degrees) || !finite64(elevation_degrees) || !finite64(low) || !finite64(high) || low > high || low < -90.0f64 || high > 90.0f64 { ret (zero, Invalid) }
    let turned = camera.azimuth_degrees + azimuth_degrees
    let azimuth = turned - 360.0f64 * math.floor[f64]((turned + 180.0f64) / 360.0f64)
    var elevation = camera.elevation_degrees + elevation_degrees
    if elevation < low { elevation = low }
    if elevation > high { elevation = high }
    if !finite64(azimuth) { ret (zero, Invalid) }
    ret (Camera3d { azimuth_degrees: azimuth, elevation_degrees: elevation, distance: camera.distance }, ok)
}

// Unit-cube camera coordinates; positive depth is nearer the viewer.
fn project3d(camera: *const Projection3d, x: f64, y: f64, z: f64) -> (Coord, f64, err) {
    let right = -camera.sin_azimuth * x + camera.cos_azimuth * y
    let up = -camera.sin_elevation * camera.cos_azimuth * x - camera.sin_elevation * camera.sin_azimuth * y + camera.cos_elevation * z
    let depth = camera.cos_elevation * camera.cos_azimuth * x + camera.cos_elevation * camera.sin_azimuth * y + camera.sin_elevation * z
    let denominator = camera.distance - depth
    if !finite64(denominator) || denominator <= 0.0f64 { ret (zero, 0.0f64, Invalid) }
    let factor = camera.distance / denominator
    let point = Coord { x: f32(right * factor), y: f32(up * factor) }
    if !finite(point.x) || !finite(point.y) || !finite64(depth) { ret (zero, 0.0f64, Invalid) }
    ret (point, depth, ok)
}

// Fit all eight projected cube corners with one scale, so 3-D axes keep the
// same camera and visual proportions across scatter, bars and surfaces.
fn viewport3d(camera: Camera3d, bounds: geometry.Rect, corners: []Coord) -> (Viewport3d, err) {
    if !finite64(camera.azimuth_degrees) || !finite64(camera.elevation_degrees) || !finite64(camera.distance) || camera.azimuth_degrees < -360.0f64 || camera.azimuth_degrees > 360.0f64 || camera.elevation_degrees < -90.0f64 || camera.elevation_degrees > 90.0f64 || camera.distance < 3.0f64 || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if corners.len < 8usize { ret (zero, TooLarge) }
    let azimuth = camera.azimuth_degrees * 0.017453292519943295f64
    let elevation = camera.elevation_degrees * 0.017453292519943295f64
    let projection = Projection3d { sin_azimuth: math.sin[f64](azimuth), cos_azimuth: math.cos[f64](azimuth), sin_elevation: math.sin[f64](elevation), cos_elevation: math.cos[f64](elevation), distance: camera.distance }
    var u_lo = 0.0f64
    var u_hi = 0.0f64
    var v_lo = 0.0f64
    var v_hi = 0.0f64
    var i = 0usize
    while i < 8usize {
        var nx = -1.0f64
        var ny = -1.0f64
        var nz = -1.0f64
        if i % 2usize != 0usize { nx = 1.0f64 }
        if (i / 2usize) % 2usize != 0usize { ny = 1.0f64 }
        if i >= 4usize { nz = 1.0f64 }
        let (raw, unused, projection_error) = project3d(&projection, nx, ny, nz)
        if projection_error != ok { ret (zero, projection_error) }
        corners[i] = raw
        if i == 0usize || f64(raw.x) < u_lo { u_lo = f64(raw.x) }
        if i == 0usize || f64(raw.x) > u_hi { u_hi = f64(raw.x) }
        if i == 0usize || f64(raw.y) < v_lo { v_lo = f64(raw.y) }
        if i == 0usize || f64(raw.y) > v_hi { v_hi = f64(raw.y) }
        i += 1usize
    }
    let scale = math.min[f64](f64(bounds.width) / (1.12f64 * (u_hi - u_lo)), f64(bounds.height) / (1.12f64 * (v_hi - v_lo)))
    if !finite64(scale) || scale <= 0.0f64 { ret (zero, Invalid) }
    let result = Viewport3d { projection: projection, u_center: u_lo + (u_hi - u_lo) * 0.5f64, v_center: v_lo + (v_hi - v_lo) * 0.5f64, scale: scale, x_center: f64(bounds.x) + f64(bounds.width) * 0.5f64, y_center: f64(bounds.y) + f64(bounds.height) * 0.5f64 }
    i = 0usize
    while i < 8usize {
        let point = Coord { x: f32(result.x_center + (f64(corners[i].x) - result.u_center) * result.scale), y: f32(result.y_center - (f64(corners[i].y) - result.v_center) * result.scale) }
        if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
        corners[i] = point
        i += 1usize
    }
    ret (result, ok)
}

fn project3d_view(view: *const Viewport3d, x: f64, y: f64, z: f64) -> (Coord, f64, err) {
    let (raw, depth, projection_error) = project3d(&view.projection, x, y, z)
    if projection_error != ok { ret (zero, 0.0f64, projection_error) }
    let point = Coord { x: f32(view.x_center + (f64(raw.x) - view.u_center) * view.scale), y: f32(view.y_center - (f64(raw.y) - view.v_center) * view.scale) }
    if !finite(point.x) || !finite(point.y) { ret (zero, 0.0f64, Invalid) }
    ret (point, depth, ok)
}

fn cube_frame3d(corners: []const Coord, edges: []Segment) -> err {
    if corners.len < 8usize || edges.len < 12usize { ret TooLarge }
    var vertex = 0usize
    var edge = 0usize
    while vertex < 8usize {
        if vertex % 2usize == 0usize {
            edges[edge] = Segment { from: corners[vertex], to: corners[vertex + 1usize] }
            edge += 1usize
        }
        if (vertex / 2usize) % 2usize == 0usize {
            edges[edge] = Segment { from: corners[vertex], to: corners[vertex + 2usize] }
            edge += 1usize
        }
        if vertex < 4usize {
            edges[edge] = Segment { from: corners[vertex], to: corners[vertex + 4usize] }
            edge += 1usize
        }
        vertex += 1usize
    }
    ret ok
}

fn scatter3d_depth_compare(key: *Scatter3dOrder, left: usize, right: usize) -> i32 {
    if key.depths[left] < key.depths[right] { ret -1i32 }
    if key.depths[left] > key.depths[right] { ret 1i32 }
    if left < right { ret -1i32 }
    if left > right { ret 1i32 }
    ret 0i32
}

// Perspective projection with a depth-sorted bubble layer. Markers are drawn
// far-to-near; the twelve cube edges are a separate background layer.
fn scatter3d(x: []const f64, y: []const f64, z: []const f64, camera: Camera3d, bounds: geometry.Rect, storage: *Scatter3dStorage) -> (Scatter3dLayout, err) {
    if x.len == 0usize || x.len != y.len || x.len != z.len { ret (zero, Invalid) }
    let n = x.len
    if storage.points.len < n || storage.depths.len < n || storage.order.len < n || storage.bubbles.len < n || storage.corners.len < 8usize || storage.edges.len < 12usize { ret (zero, TooLarge) }
    var x_lo = x[0usize]
    var x_hi = x_lo
    var y_lo = y[0usize]
    var y_hi = y_lo
    var z_lo = z[0usize]
    var z_hi = z_lo
    var i = 0usize
    while i < n {
        if !finite64(x[i]) || !finite64(y[i]) || !finite64(z[i]) { ret (zero, Invalid) }
        x_lo = math.min[f64](x_lo, x[i])
        x_hi = math.max[f64](x_hi, x[i])
        y_lo = math.min[f64](y_lo, y[i])
        y_hi = math.max[f64](y_hi, y[i])
        z_lo = math.min[f64](z_lo, z[i])
        z_hi = math.max[f64](z_hi, z[i])
        i += 1usize
    }
    let x_span = x_hi - x_lo
    let y_span = y_hi - y_lo
    let z_span = z_hi - z_lo
    if !finite64(x_span) || !finite64(y_span) || !finite64(z_span) || !finite(f32(x_lo)) || !finite(f32(x_hi)) || !finite(f32(y_lo)) || !finite(f32(y_hi)) || !finite(f32(z_lo)) || !finite(f32(z_hi)) { ret (zero, Invalid) }
    let (view, view_error) = viewport3d(camera, bounds, storage.corners[..8usize])
    if view_error != ok { ret (zero, view_error) }
    try cube_frame3d(storage.corners[..8usize], storage.edges[..12usize])
    i = 0usize
    while i < n {
        var nx = 0.0f64
        var ny = 0.0f64
        var nz = 0.0f64
        if x_span > 0.0f64 { nx = 2.0f64 * ((x[i] - x_lo) / x_span) - 1.0f64 }
        if y_span > 0.0f64 { ny = 2.0f64 * ((y[i] - y_lo) / y_span) - 1.0f64 }
        if z_span > 0.0f64 { nz = 2.0f64 * ((z[i] - z_lo) / z_span) - 1.0f64 }
        let (point, depth, projection_error) = project3d_view(&view, nx, ny, nz)
        if projection_error != ok { ret (zero, projection_error) }
        storage.points[i] = point
        storage.depths[i] = depth
        storage.order[i] = i
        i += 1usize
    }
    var key = Scatter3dOrder { depths: storage.depths[..n] }
    sort.in_place_by[usize, Scatter3dOrder](storage.order[..n], &key, scatter3d_depth_compare)
    i = 0usize
    while i < n {
        let source = storage.order[i]
        let diameter = f32(6.0f64 * view.projection.distance / (view.projection.distance - storage.depths[source]))
        let point = storage.points[source]
        if !finite(diameter) || diameter <= 0.0 { ret (zero, Invalid) }
        storage.bubbles[i] = geometry.rect(point.x - diameter * 0.5, point.y - diameter * 0.5, diameter, diameter)
        i += 1usize
    }
    let marks = Layout { kind: .Bubble, coords: storage.points[..n], segments: zero, bars: storage.bubbles[..n], x_min: f32(x_lo), x_max: f32(x_hi), y_min: f32(y_lo), y_max: f32(y_hi) }
    let frame = Layout { kind: .Rug, coords: zero, segments: storage.edges[..12usize], bars: zero, x_min: f32(x_lo), x_max: f32(x_hi), y_min: f32(y_lo), y_max: f32(y_hi) }
    ret (Scatter3dLayout { marks: marks, frame: frame, points: storage.points[..n], depths: storage.depths[..n], order: storage.order[..n], corners: storage.corners[..8usize], x_min: x_lo, x_max: x_hi, y_min: y_lo, y_max: y_hi, z_min: z_lo, z_max: z_hi }, ok)
}

// A joint x/y histogram extruded into count-height prisms. `bin2d` owns the
// boundary convention and row-major counts; each nonempty cell emits the top
// and two camera-facing side quads in far-to-near painter order.
fn histogram3d(x: []const f32, y: []const f32, x_min: f32, x_max: f32, y_min: f32, y_max: f32, columns: usize, rows: usize, camera: Camera3d, bounds: geometry.Rect, storage: *Histogram3dStorage) -> (Histogram3dLayout, err) {
    if columns == 0usize || rows == 0usize || camera.elevation_degrees <= 0.0f64 || camera.elevation_degrees >= 90.0f64 { ret (zero, Invalid) }
    if columns > storage.counts.len / rows || columns > storage.cells.len / rows { ret (zero, TooLarge) }
    let bins = columns * rows
    if bins > storage.faces.len / 3usize || bins > storage.depths.len / 3usize || bins > storage.order.len / 3usize || bins > storage.face_kinds.len / 3usize || bins > storage.vertices.len / 12usize || storage.corners.len < 8usize || storage.edges.len < 12usize { ret (zero, TooLarge) }
    let bin_bounds = geometry.rect(0.0, 0.0, f32(columns), f32(rows))
    let (grid, bin_error) = bin2d(x, y, x_min, x_max, y_min, y_max, bin_bounds, columns, rows, storage.counts[..bins], storage.cells[..bins])
    if bin_error != ok { ret (zero, bin_error) }
    let (view, view_error) = viewport3d(camera, bounds, storage.corners[..8usize])
    if view_error != ok { ret (zero, view_error) }
    try cube_frame3d(storage.corners[..8usize], storage.edges[..12usize])
    var face_count = 0usize
    var cell = 0usize
    while cell < bins {
        if grid.counts[cell] > 0u64 {
            let column = cell % columns
            let row = cell / columns
            let x0 = -1.0f64 + 2.0f64 * (f64(column) + 0.12f64) / f64(columns)
            let x1 = -1.0f64 + 2.0f64 * (f64(column) + 0.88f64) / f64(columns)
            let y0 = 1.0f64 - 2.0f64 * (f64(row) + 0.88f64) / f64(rows)
            let y1 = 1.0f64 - 2.0f64 * (f64(row) + 0.12f64) / f64(rows)
            let top = -1.0f64 + 2.0f64 * f64(grid.counts[cell]) / f64(grid.max_count)
            var x_side = x0
            var y_side = y0
            if view.projection.cos_azimuth >= 0.0f64 { x_side = x1 }
            if view.projection.sin_azimuth >= 0.0f64 { y_side = y1 }
            var side = 0usize
            while side < 3usize {
                var depth_sum = 0.0f64
                var corner = 0usize
                while corner < 4usize {
                    var vx = x0
                    var vy = y0
                    var vz = top
                    if side == 0usize {
                        if corner == 1usize || corner == 2usize { vx = x1 }
                        if corner >= 2usize { vy = y1 }
                    } else if side == 1usize {
                        vx = x_side
                        if corner == 1usize || corner == 2usize { vy = y1 }
                        vz = -1.0f64
                        if corner >= 2usize { vz = top }
                    } else {
                        vy = y_side
                        if corner == 1usize || corner == 2usize { vx = x1 }
                        vz = -1.0f64
                        if corner >= 2usize { vz = top }
                    }
                    let (point, depth, projection_error) = project3d_view(&view, vx, vy, vz)
                    if projection_error != ok { ret (zero, projection_error) }
                    storage.vertices[face_count * 4usize + corner] = point
                    depth_sum += depth
                    corner += 1usize
                }
                storage.faces[face_count] = Layout { kind: .Area, coords: storage.vertices[face_count * 4usize..face_count * 4usize + 4usize], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }
                storage.depths[face_count] = depth_sum * 0.25f64
                storage.order[face_count] = face_count
                if side == 0usize { storage.face_kinds[face_count] = .Top }
                if side == 1usize { storage.face_kinds[face_count] = .XSide }
                if side == 2usize { storage.face_kinds[face_count] = .YSide }
                face_count += 1usize
                side += 1usize
            }
        }
        cell += 1usize
    }
    var key = Scatter3dOrder { depths: storage.depths[..face_count] }
    sort.in_place_by[usize, Scatter3dOrder](storage.order[..face_count], &key, scatter3d_depth_compare)
    let frame = Layout { kind: .Rug, coords: zero, segments: storage.edges[..12usize], bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }
    ret (Histogram3dLayout { faces: storage.faces[..face_count], depths: storage.depths[..face_count], order: storage.order[..face_count], face_kinds: storage.face_kinds[..face_count], counts: storage.counts[..bins], frame: frame, corners: storage.corners[..8usize], columns: columns, rows: rows, max_count: grid.max_count, total_count: grid.total_count }, ok)
}

// Project one regular row-major scalar grid as both shaded quads and independent
// row/column wire segments. Row zero is the high-y edge. The caller chooses
// whether to paint filled faces, wires, or both from this shared geometry.
fn surface3d_grid(values: []const f64, columns: usize, camera: Camera3d, bounds: geometry.Rect, storage: *Surface3dStorage) -> (Surface3dLayout, err) {
    if columns < 2usize || values.len < 4usize || values.len % columns != 0usize { ret (zero, Invalid) }
    let rows = values.len / columns
    if rows < 2usize { ret (zero, Invalid) }
    let quads = (columns - 1usize) * (rows - 1usize)
    if storage.points.len < values.len || storage.depths.len < values.len || storage.faces.len < quads || storage.face_depths.len < quads || storage.face_values.len < quads || storage.order.len < quads || quads > storage.face_vertices.len / 4usize || storage.corners.len < 8usize || storage.edges.len < 12usize { ret (zero, TooLarge) }
    if rows > storage.wires.len / (columns - 1usize) { ret (zero, TooLarge) }
    let horizontal = rows * (columns - 1usize)
    if columns > (storage.wires.len - horizontal) / (rows - 1usize) { ret (zero, TooLarge) }
    let wire_count = horizontal + columns * (rows - 1usize)
    var low = values[0usize]
    var high = low
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        low = math.min[f64](low, values[i])
        high = math.max[f64](high, values[i])
        i += 1usize
    }
    let span = high - low
    if !finite64(span) || !finite(f32(low)) || !finite(f32(high)) { ret (zero, Invalid) }
    let (view, view_error) = viewport3d(camera, bounds, storage.corners[..8usize])
    if view_error != ok { ret (zero, view_error) }
    try cube_frame3d(storage.corners[..8usize], storage.edges[..12usize])
    i = 0usize
    while i < values.len {
        let row = i / columns
        let column = i % columns
        let nx = -1.0f64 + 2.0f64 * f64(column) / f64(columns - 1usize)
        let ny = 1.0f64 - 2.0f64 * f64(row) / f64(rows - 1usize)
        var nz = 0.0f64
        if span > 0.0f64 { nz = -1.0f64 + 2.0f64 * (values[i] - low) / span }
        let (point, depth, projection_error) = project3d_view(&view, nx, ny, nz)
        if projection_error != ok { ret (zero, projection_error) }
        storage.points[i] = point
        storage.depths[i] = depth
        i += 1usize
    }
    var face = 0usize
    var wire = 0usize
    var row = 0usize
    while row < rows {
        var column = 0usize
        while column < columns {
            let at = row * columns + column
            if column + 1usize < columns {
                storage.wires[wire] = Segment { from: storage.points[at], to: storage.points[at + 1usize] }
                wire += 1usize
            }
            if row + 1usize < rows {
                storage.wires[wire] = Segment { from: storage.points[at], to: storage.points[at + columns] }
                wire += 1usize
            }
            if column + 1usize < columns && row + 1usize < rows {
                let a = at
                let b = at + 1usize
                let c = at + columns + 1usize
                let d = at + columns
                let first = face * 4usize
                storage.face_vertices[first] = storage.points[a]
                storage.face_vertices[first + 1usize] = storage.points[b]
                storage.face_vertices[first + 2usize] = storage.points[c]
                storage.face_vertices[first + 3usize] = storage.points[d]
                storage.faces[face] = Layout { kind: .Area, coords: storage.face_vertices[first..first + 4usize], segments: zero, bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: f32(low), y_max: f32(high) }
                storage.face_depths[face] = (storage.depths[a] + storage.depths[b] + storage.depths[c] + storage.depths[d]) * 0.25f64
                storage.face_values[face] = (values[a] + values[b] + values[c] + values[d]) * 0.25f64
                storage.order[face] = face
                face += 1usize
            }
            column += 1usize
        }
        row += 1usize
    }
    if face != quads || wire != wire_count { ret (zero, Invalid) }
    var key = Scatter3dOrder { depths: storage.face_depths[..quads] }
    sort.in_place_by[usize, Scatter3dOrder](storage.order[..quads], &key, scatter3d_depth_compare)
    let wires = Layout { kind: .Rug, coords: zero, segments: storage.wires[..wire_count], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: f32(low), y_max: f32(high) }
    let frame = Layout { kind: .Rug, coords: zero, segments: storage.edges[..12usize], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: f32(low), y_max: f32(high) }
    ret (Surface3dLayout { faces: storage.faces[..quads], face_depths: storage.face_depths[..quads], face_values: storage.face_values[..quads], order: storage.order[..quads], wireframe: wires, frame: frame, points: storage.points[..values.len], depths: storage.depths[..values.len], values: values, corners: storage.corners[..8usize], columns: columns, rows: rows, value_min: low, value_max: high }, ok)
}

// Product-Gaussian KDE values feed the same projected grid as a general
// wireframe. Bandwidths are explicit; there is no hidden data-dependent fit.
fn density_surface3d(x: []const f64, y: []const f64, x_min: f64, x_max: f64, y_min: f64, y_max: f64, bandwidth_x: f64, bandwidth_y: f64, camera: Camera3d, bounds: geometry.Rect, grid_x: []f64, grid_y: []f64, values: []f64, storage: *Surface3dStorage) -> (Surface3dLayout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || !finite64(x_min) || !finite64(x_max) || !finite64(y_min) || !finite64(y_max) || x_max <= x_min || y_max <= y_min || !finite64(bandwidth_x) || !finite64(bandwidth_y) || bandwidth_x <= 0.0f64 || bandwidth_y <= 0.0f64 || grid_x.len < 2usize || grid_y.len < 2usize { ret (zero, Invalid) }
    if grid_x.len > values.len / grid_y.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < x.len {
        if !finite64(x[i]) || !finite64(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < grid_x.len {
        grid_x[i] = x_min + (x_max - x_min) * f64(i) / f64(grid_x.len - 1usize)
        i += 1usize
    }
    i = 0usize
    while i < grid_y.len {
        grid_y[i] = y_max - (y_max - y_min) * f64(i) / f64(grid_y.len - 1usize)
        i += 1usize
    }
    let needed = grid_x.len * grid_y.len
    let kde_error = stat.kde2d(x, y, bandwidth_x, bandwidth_y, grid_x, grid_y, values[..needed])
    if kde_error != ok { ret (zero, Invalid) }
    let (surface, surface_error) = surface3d_grid(values[..needed], grid_x.len, camera, bounds, storage)
    ret (surface, surface_error)
}

fn wireframe3d(values: []const f64, columns: usize, camera: Camera3d, bounds: geometry.Rect, storage: *Surface3dStorage) -> (Surface3dLayout, err) {
    let (surface, surface_error) = surface3d_grid(values, columns, camera, bounds, storage)
    ret (surface, surface_error)
}

// Two-parameter Weibull probability paper. `total_count` includes units
// right-censored after the final failure; earlier removals need a different
// plotting-position estimator. Shape and scale are caller-supplied, so the
// reference can represent either a fitted or historical distribution.
fn weibull_probability_plot(sorted_failures: []const f64, total_count: usize, shape: f64, scale: f64, domain_min: f64, domain_max: f64, bounds: geometry.Rect, points: []Coord, reference: []Segment, tick_storage: []Tick) -> (ProbabilityLayout, err) {
    if sorted_failures.len < 2usize { ret (zero, Empty) }
    if total_count < sorted_failures.len || !finite64(shape) || !finite64(scale) || shape <= 0.0f64 || scale <= 0.0f64 || !finite64(domain_min) || !finite64(domain_max) || domain_min <= 0.0f64 || domain_max <= domain_min || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if points.len < sorted_failures.len || reference.len == 0usize || tick_storage.len < 7usize { ret (zero, TooLarge) }
    let log_min = math.log[f64](domain_min)
    let log_max = math.log[f64](domain_max)
    let log_scale = math.log[f64](scale)
    var paper_lo = weibull_paper(0.01f64)
    var paper_hi = weibull_paper(0.99f64)
    let first_p = 0.7f64 / (f64(total_count) + 0.4f64)
    let last_p = (f64(sorted_failures.len) - 0.3f64) / (f64(total_count) + 0.4f64)
    if first_p < 0.01f64 { paper_lo = weibull_paper(first_p) }
    if last_p > 0.99f64 { paper_hi = weibull_paper(last_p) }
    if !finite64(log_min) || !finite64(log_max) || !finite64(log_scale) || log_max <= log_min || !finite(f32(log_min)) || !finite(f32(log_max)) || f32(log_max) <= f32(log_min) || !finite64(paper_lo) || !finite64(paper_hi) { ret (zero, Invalid) }
    var i = 0usize
    while i < sorted_failures.len {
        let value = sorted_failures[i]
        if !finite64(value) || value < domain_min || value > domain_max || (i > 0usize && value < sorted_failures[i - 1usize]) { ret (zero, Invalid) }
        let p = (f64(i) + 0.7f64) / (f64(total_count) + 0.4f64)
        let paper = weibull_paper(p)
        let x = bounds.x + bounds.width * f32((math.log[f64](value) - log_min) / (log_max - log_min))
        let y = bounds.y + bounds.height * f32((paper_hi - paper) / (paper_hi - paper_lo))
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        i += 1usize
    }
    var line_lo = shape * (log_min - log_scale)
    var line_hi = shape * (log_max - log_scale)
    if !finite64(line_lo) || !finite64(line_hi) { ret (zero, Invalid) }
    if line_lo < paper_lo { line_lo = paper_lo }
    if line_hi > paper_hi { line_hi = paper_hi }
    if line_hi <= line_lo { ret (zero, Invalid) }
    let from_x = bounds.x + bounds.width * f32((log_scale + line_lo / shape - log_min) / (log_max - log_min))
    let to_x = bounds.x + bounds.width * f32((log_scale + line_hi / shape - log_min) / (log_max - log_min))
    let from_y = bounds.y + bounds.height * f32((paper_hi - line_lo) / (paper_hi - paper_lo))
    let to_y = bounds.y + bounds.height * f32((paper_hi - line_hi) / (paper_hi - paper_lo))
    if !finite(from_x) || !finite(to_x) || !finite(from_y) || !finite(to_y) { ret (zero, Invalid) }
    reference[0usize] = Segment { from: Coord { x: from_x, y: from_y }, to: Coord { x: to_x, y: to_y } }
    let probabilities = [7]f64{ 0.01f64, 0.05f64, 0.25f64, 0.5f64, 0.75f64, 0.95f64, 0.99f64 }
    i = 0usize
    while i < probabilities.len {
        tick_storage[i] = Tick { value: f32(probabilities[i]), fraction: f32((weibull_paper(probabilities[i]) - paper_lo) / (paper_hi - paper_lo)) }
        i += 1usize
    }
    let observed = Layout { kind: .Scatter, coords: points[..sorted_failures.len], segments: zero, bars: zero, x_min: f32(log_min), x_max: f32(log_max), y_min: f32(paper_lo), y_max: f32(paper_hi) }
    let fitted = Layout { kind: .Line, coords: zero, segments: reference[..1usize], bars: zero, x_min: f32(log_min), x_max: f32(log_max), y_min: f32(paper_lo), y_max: f32(paper_hi) }
    ret (ProbabilityLayout { observations: observed, reference: fitted, probability_ticks: tick_storage[..7usize] }, ok)
}

// An observed-value axis against nonlinearly spaced probability paper.
// Plotting positions are (i + 1/2)/n; the returned ticks carry percentage
// values and transformed fractions, while the fitted line is clipped to both
// the numeric domain and the fixed 1%-99% paper. Caller owns all output.
fn probability_plot(sorted: []const f64, family: ProbabilityFamily, location: f64, scale: f64, domain_min: f64, domain_max: f64, bounds: geometry.Rect, points: []Coord, reference: []Segment, tick_storage: []Tick) -> (ProbabilityLayout, err) {
    if sorted.len < 2usize { ret (zero, Empty) }
    if !finite64(location) || !finite64(scale) || scale <= 0.0f64 || !finite64(domain_min) || !finite64(domain_max) || domain_max <= domain_min || !finite64(domain_max - domain_min) || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    let x_min = f32(domain_min)
    let x_max = f32(domain_max)
    if !finite(x_min) || !finite(x_max) || x_max <= x_min { ret (zero, Invalid) }
    if points.len < sorted.len || reference.len == 0usize || tick_storage.len < 7usize { ret (zero, TooLarge) }
    let paper_lo = probability_paper_quantile(family, 0.01f64)
    let paper_hi = probability_paper_quantile(family, 0.99f64)
    if !finite64(paper_lo) || !finite64(paper_hi) || paper_hi <= paper_lo || !finite(f32(paper_lo)) || !finite(f32(paper_hi)) { ret (zero, Invalid) }
    let sample_count = f64(sorted.len)
    var i = 0usize
    while i < sorted.len {
        let value = sorted[i]
        if !finite64(value) || value < domain_min || value > domain_max || (i > 0usize && value < sorted[i - 1usize]) { ret (zero, Invalid) }
        let p = (f64(i) + 0.5f64) / sample_count
        let paper = probability_paper_quantile(family, p)
        let x = bounds.x + bounds.width * f32((value - domain_min) / (domain_max - domain_min))
        let y = bounds.y + bounds.height * f32((paper_hi - paper) / (paper_hi - paper_lo))
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        i += 1usize
    }
    var line_lo = (domain_min - location) / scale
    var line_hi = (domain_max - location) / scale
    if !finite64(line_lo) || !finite64(line_hi) { ret (zero, Invalid) }
    if line_lo < paper_lo { line_lo = paper_lo }
    if line_hi > paper_hi { line_hi = paper_hi }
    if line_hi <= line_lo { ret (zero, Invalid) }
    let from_x = bounds.x + bounds.width * f32((location + scale * line_lo - domain_min) / (domain_max - domain_min))
    let to_x = bounds.x + bounds.width * f32((location + scale * line_hi - domain_min) / (domain_max - domain_min))
    let from_y = bounds.y + bounds.height * f32((paper_hi - line_lo) / (paper_hi - paper_lo))
    let to_y = bounds.y + bounds.height * f32((paper_hi - line_hi) / (paper_hi - paper_lo))
    if !finite(from_x) || !finite(to_x) || !finite(from_y) || !finite(to_y) { ret (zero, Invalid) }
    reference[0usize] = Segment { from: Coord { x: from_x, y: from_y }, to: Coord { x: to_x, y: to_y } }
    let probabilities = [7]f64{ 0.01f64, 0.05f64, 0.25f64, 0.5f64, 0.75f64, 0.95f64, 0.99f64 }
    i = 0usize
    while i < probabilities.len {
        let position = f32((probability_paper_quantile(family, probabilities[i]) - paper_lo) / (paper_hi - paper_lo))
        if !finite(position) || position < 0.0 || position > 1.0 { ret (zero, Invalid) }
        tick_storage[i] = Tick { value: f32(probabilities[i]), fraction: position }
        i += 1usize
    }
    let observed = Layout { kind: .Scatter, coords: points[..sorted.len], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: f32(paper_lo), y_max: f32(paper_hi) }
    let fitted = Layout { kind: .Line, coords: zero, segments: reference[..1usize], bars: zero, x_min: x_min, x_max: x_max, y_min: f32(paper_lo), y_max: f32(paper_hi) }
    ret (ProbabilityLayout { observations: observed, reference: fitted, probability_ticks: tick_storage[..7usize] }, ok)
}

// Normal Q-Q positions use (i + 1/2) / n. The reference joins the sample's
// R7 quartiles against the theoretical normal quartiles.
fn qq_normal(sorted: []const f64, bounds: geometry.Rect, points: []Coord, reference: []Segment) -> (Layout, err) {
    if sorted.len < 2usize { ret (zero, Empty) }
    if points.len < sorted.len || reference.len < 1usize { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var ymin = f32(sorted[0usize])
    var ymax = f32(sorted[sorted.len - 1usize])
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
        if ymin == ymax {
            if ymin > 0.0 { ymin *= 0.5 } else { ymax *= 0.5 }
        }
    }
    let n = f64(sorted.len)
    let xmin = f32(special.normal_quantile(0.5f64 / n))
    let xmax = f32(special.normal_quantile((n - 0.5f64) / n))
    i = 0usize
    while i < sorted.len {
        let theoretical = f32(special.normal_quantile((f64(i) + 0.5f64) / n))
        points[i] = Coord {
            x: mapped(theoretical, xmin, xmax, bounds.x, bounds.width),
            y: bounds.y + bounds.height - mapped(f32(sorted[i]), ymin, ymax, 0.0, bounds.height),
        }
        i += 1usize
    }
    let (q1, first_ok) = stat.quantile(sorted, 0.25f64, .R7)
    let (q3, third_ok) = stat.quantile(sorted, 0.75f64, .R7)
    if !first_ok || !third_ok { ret (zero, Invalid) }
    let theory_q1 = f32(special.normal_quantile(0.25f64))
    let theory_q3 = f32(special.normal_quantile(0.75f64))
    reference[0usize] = Segment {
        from: Coord { x: mapped(theory_q1, xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(f32(q1), ymin, ymax, 0.0, bounds.height) },
        to: Coord { x: mapped(theory_q3, xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(f32(q3), ymin, ymax, 0.0, bounds.height) },
    }
    ret (Layout { kind: .Qq, coords: points[..sorted.len], segments: reference[..1usize], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// Compare the empirical plotting positions with a caller-specified normal CDF.
fn pp_normal(sorted: []const f64, mean: f64, deviation: f64, bounds: geometry.Rect, points: []Coord, reference: []Segment) -> (Layout, err) {
    if sorted.len < 2usize { ret (zero, Empty) }
    if points.len < sorted.len || reference.len < 1usize { ret (zero, TooLarge) }
    if !valid_bounds(bounds) || !finite64(mean) || !finite64(deviation) || deviation <= 0.0f64 { ret (zero, Invalid) }
    var i = 0usize
    while i < sorted.len {
        if !finite64(sorted[i]) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        let z = (sorted[i] - mean) / deviation
        if !finite64(z) { ret (zero, Invalid) }
        let theoretical = special.normal_cdf(z)
        let empirical = (f64(i) + 0.5f64) / f64(sorted.len)
        points[i] = Coord {
            x: bounds.x + bounds.width * f32(theoretical),
            y: bounds.y + bounds.height * f32(1.0f64 - empirical),
        }
        i += 1usize
    }
    reference[0usize] = Segment {
        from: Coord { x: bounds.x, y: bounds.y + bounds.height },
        to: Coord { x: bounds.x + bounds.width, y: bounds.y },
    }
    ret (Layout { kind: .Pp, coords: points[..sorted.len], segments: reference[..1usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }, ok)
}

// A pointy-top, offset-row hex lattice. Each observation is assigned to its
// nearest valid centre, considering the three neighbouring rows and columns;
// this also assigns points on panel boundaries without dropping counts.
// Six-vertex Area polygons are inset slightly to separate adjacent bins.
fn hexbin(x: []const f32, y: []const f32, x_min: f32, x_max: f32, y_min: f32, y_max: f32, bounds: geometry.Rect, columns: usize, rows: usize, cells: []HexCell, vertices: []Coord, layers: []Layout) -> (HexbinLayout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || !finite(x_min) || !finite(x_max) || !finite(y_min) || !finite(y_max) || x_max <= x_min || y_max <= y_min || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || columns == 0usize || rows == 0usize { ret (zero, Invalid) }
    if columns > cells.len / rows { ret (zero, TooLarge) }
    let needed = columns * rows
    if vertices.len / 6usize < needed || layers.len < needed { ret (zero, TooLarge) }
    let sqrt3 = 1.7320508f32
    let horizontal_radius = bounds.width / (sqrt3 * (f32(columns) + 0.5))
    let vertical_radius = bounds.height / (1.5 * f32(rows - 1usize) + 2.0)
    var radius = horizontal_radius
    if vertical_radius < radius { radius = vertical_radius }
    if !finite(radius) || radius < 3.0 { ret (zero, TooLarge) }
    let step_x = sqrt3 * radius
    let step_y = 1.5 * radius
    let margin_x = (bounds.width - step_x * (f32(columns) + 0.5)) * 0.5
    let margin_y = (bounds.height - radius * (1.5 * f32(rows - 1usize) + 2.0)) * 0.5
    let first_x = bounds.x + margin_x + step_x * 0.5
    let first_y = bounds.y + margin_y + radius
    var row = 0usize
    while row < rows {
        var column = 0usize
        while column < columns {
            let offset = f32(row % 2usize) * step_x * 0.5
            cells[row * columns + column] = HexCell { center: Coord { x: first_x + f32(column) * step_x + offset, y: first_y + f32(row) * step_y }, count: 0u64 }
            column += 1usize
        }
        row += 1usize
    }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
        let px = bounds.x + bounds.width * (x[i] - x_min) / (x_max - x_min)
        let py = bounds.y + bounds.height * (1.0 - (y[i] - y_min) / (y_max - y_min))
        if !finite(px) || !finite(py) { ret (zero, Invalid) }
        var row_position = (py - first_y) / step_y
        if row_position < 0.0 { row_position = 0.0 }
        if row_position > f32(rows - 1usize) { row_position = f32(rows - 1usize) }
        let near_row = i64(math.round[f32](row_position))
        var best = needed
        var best_distance = 0.0f64
        var candidate_row = near_row - 1i64
        while candidate_row <= near_row + 1i64 {
            if candidate_row >= 0i64 && candidate_row < i64(rows) {
                let offset = f32(usize(candidate_row) % 2usize) * step_x * 0.5
                var column_position = (px - first_x - offset) / step_x
                if column_position < 0.0 { column_position = 0.0 }
                if column_position > f32(columns - 1usize) { column_position = f32(columns - 1usize) }
                let near_column = i64(math.round[f32](column_position))
                var candidate_column = near_column - 1i64
                while candidate_column <= near_column + 1i64 {
                    if candidate_column >= 0i64 && candidate_column < i64(columns) {
                        let index = usize(candidate_row) * columns + usize(candidate_column)
                        let dx = f64(px - cells[index].center.x)
                        let dy = f64(py - cells[index].center.y)
                        let distance = dx * dx + dy * dy
                        if best == needed || distance < best_distance || (distance == best_distance && index < best) {
                            best = index
                            best_distance = distance
                        }
                    }
                    candidate_column += 1i64
                }
            }
            candidate_row += 1i64
        }
        if best == needed { ret (zero, Invalid) }
        cells[best].count += 1u64
        i += 1usize
    }
    let drawn_radius = radius * 0.94
    let half_width = sqrt3 * drawn_radius * 0.5
    var max_count = 0u64
    i = 0usize
    while i < needed {
        let center = cells[i].center
        if cells[i].count > max_count { max_count = cells[i].count }
        let first = i * 6usize
        vertices[first] = Coord { x: center.x, y: center.y - drawn_radius }
        vertices[first + 1usize] = Coord { x: center.x + half_width, y: center.y - drawn_radius * 0.5 }
        vertices[first + 2usize] = Coord { x: center.x + half_width, y: center.y + drawn_radius * 0.5 }
        vertices[first + 3usize] = Coord { x: center.x, y: center.y + drawn_radius }
        vertices[first + 4usize] = Coord { x: center.x - half_width, y: center.y + drawn_radius * 0.5 }
        vertices[first + 5usize] = Coord { x: center.x - half_width, y: center.y - drawn_radius * 0.5 }
        layers[i] = Layout { kind: .Area, coords: vertices[first..first + 6usize], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }
        i += 1usize
    }
    ret (HexbinLayout { cells: cells[..needed], hexes: layers[..needed], max_count: max_count, total_count: u64(x.len) }, ok)
}

fn cell_rect(bounds: geometry.Rect, column: usize, row: usize, columns: usize, rows: usize) -> geometry.Rect {
    let x0 = bounds.x + bounds.width * f32(column) / f32(columns)
    let x1 = bounds.x + bounds.width * f32(column + 1usize) / f32(columns)
    let y0 = bounds.y + bounds.height * f32(row) / f32(rows)
    let y1 = bounds.y + bounds.height * f32(row + 1usize) / f32(rows)
    ret geometry.rect(x0, y0, x1 - x0, y1 - y0)
}

// Fixed rectangular binning in row-major screen order (top row first).
// Data-domain maxima belong to the final column/row; every valid observation
// contributes exactly one count. The matrix reuses heatmap scene/SVG adapters.
fn bin2d(x: []const f32, y: []const f32, x_min: f32, x_max: f32, y_min: f32, y_max: f32, bounds: geometry.Rect, columns: usize, rows: usize, counts: []u64, cells: []Cell) -> (Bin2dLayout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || !finite(x_min) || !finite(x_max) || !finite(y_min) || !finite(y_max) || x_max <= x_min || y_max <= y_min || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || columns == 0usize || rows == 0usize { ret (zero, Invalid) }
    if columns > counts.len / rows || columns > cells.len / rows { ret (zero, TooLarge) }
    if bounds.width < f32(columns) || bounds.height < f32(rows) { ret (zero, TooLarge) }
    let needed = columns * rows
    var i = 0usize
    while i < needed {
        counts[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
        var column = columns - 1usize
        if x[i] < x_max {
            let x_share = (f64(x[i]) - f64(x_min)) / (f64(x_max) - f64(x_min))
            column = usize(math.floor[f64](x_share * f64(columns)))
            if column >= columns { column = columns - 1usize }
        }
        var row = rows - 1usize
        if y[i] > y_min {
            let y_share = (f64(y_max) - f64(y[i])) / (f64(y_max) - f64(y_min))
            row = usize(math.floor[f64](y_share * f64(rows)))
            if row >= rows { row = rows - 1usize }
        }
        counts[row * columns + column] += 1u64
        i += 1usize
    }
    var max_count = 0u64
    i = 0usize
    while i < needed {
        if counts[i] > max_count { max_count = counts[i] }
        let rect = cell_rect(bounds, i % columns, i / columns, columns, rows)
        if rect.width <= 0.0 || rect.height <= 0.0 { ret (zero, TooLarge) }
        cells[i] = Cell { rect: rect, value: f32(counts[i]) }
        i += 1usize
    }
    ret (Bin2dLayout {
        matrix: MatrixLayout { kind: .Heatmap, cells: cells[..needed], columns: columns, rows: rows, value_min: 0.0, value_max: f32(max_count) },
        counts: counts[..needed], max_count: max_count, total_count: u64(x.len),
    }, ok)
}

// Row-major values become caller-owned tiles; the renderer owns palette choice.
fn heatmap(values: []const f64, columns: usize, bounds: geometry.Rect, cells: []Cell) -> (MatrixLayout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || values.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if cells.len < values.len { ret (zero, TooLarge) }
    let rows = values.len / columns
    var lo = values[0usize]
    var hi = lo
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) || !finite(f32(values[i])) { ret (zero, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        cells[i] = Cell { rect: cell_rect(bounds, i % columns, i / columns, columns, rows), value: f32(values[i]) }
        i += 1usize
    }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..values.len], columns: columns, rows: rows, value_min: f32(lo), value_max: f32(hi) }, ok)
}

// Caller ratings define the policy; likelihood grows left-to-right and impact
// bottom-to-top. Counts stay separate from the heatmap's rating values.
fn risk_matrix(risks: []const RiskPoint, ratings: []const f64, levels: usize, bounds: geometry.Rect, counts: []u64, cells: []Cell) -> (MatrixLayout, err) {
    if levels == 0usize || ratings.len / levels != levels || ratings.len % levels != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if counts.len < ratings.len || cells.len < ratings.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < ratings.len {
        if !finite64(ratings[i]) || !finite(f32(ratings[i])) || ratings[i] < 0.0f64 { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < risks.len {
        let point = risks[i]
        if point.likelihood == 0usize || point.likelihood > levels || point.impact == 0usize || point.impact > levels { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < ratings.len {
        counts[i] = 0u64
        i += 1usize
    }
    i = 0usize
    while i < risks.len {
        let point = risks[i]
        counts[(levels - point.impact) * levels + point.likelihood - 1usize] += 1u64
        i += 1usize
    }
    let (matrix, matrix_error) = heatmap(ratings, levels, bounds, cells)
    ret (matrix, matrix_error)
}

// Compact row-major triangle: the oldest cohort has every period, the newest one.
// Each row's first count is its positive cohort size; later cells are fractions of it.
fn cohort_retention(counts: []const f64, periods: usize, bounds: geometry.Rect, gap: f32, cells: []Cell) -> (MatrixLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if periods == 0usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if periods > counts.len { ret (zero, Invalid) }
    var required = 0usize
    var width = periods
    while width > 0usize {
        if width > counts.len - required { ret (zero, Invalid) }
        required += width
        width -= 1usize
    }
    if required != counts.len { ret (zero, Invalid) }
    if cells.len < required { ret (zero, TooLarge) }
    var row = 0usize
    var used = 0usize
    while row < periods {
        let cohort_size = counts[used]
        if !finite64(cohort_size) || cohort_size <= 0.0f64 { ret (zero, Invalid) }
        var col = 0usize
        while col < periods - row {
            let value = counts[used]
            if !finite64(value) || value < 0.0f64 || value > cohort_size { ret (zero, Invalid) }
            let tile = cell_rect(bounds, col, row, periods, periods)
            if tile.width <= gap || tile.height <= gap { ret (zero, Invalid) }
            cells[used] = Cell { rect: geometry.rect(tile.x + gap * 0.5, tile.y + gap * 0.5, tile.width - gap, tile.height - gap), value: f32(value / cohort_size) }
            used += 1usize
            col += 1usize
        }
        row += 1usize
    }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..used], columns: periods, rows: periods, value_min: 0.0, value_max: 1.0 }, ok)
}

fn contour_cross(from: Coord, to: Coord, first: f64, last: f64, level: f64) -> (Coord, err) {
    let t = (level - first) / (last - first)
    if !finite64(t) || t < 0.0f64 || t > 1.0f64 { ret (zero, Invalid) }
    let point = Coord { x: from.x + f32(t) * (to.x - from.x), y: from.y + f32(t) * (to.y - from.y) }
    if !finite(point.x) || !finite(point.y) { ret (zero, Invalid) }
    ret (point, ok)
}

// Marching squares emits independent line segments for each increasing level.
// Diagonal saddles use the cell-centre value to choose the connected side.
// ponytail: O(levels*cells) independent segments; stitch paths if labels need continuity.
fn contour(values: []const f64, columns: usize, rows: usize, levels: []const f64, bounds: geometry.Rect, segments: []Segment, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize || levels.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || rows < 2usize || columns > values.len || values.len % columns != 0usize || values.len / columns != rows || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    if layers.len < levels.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < levels.len {
        if !finite64(levels[i]) || (i > 0usize && levels[i] <= levels[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var used = 0usize
    var l = 0usize
    while l < levels.len {
        let start = used
        let level = levels[l]
        var row = 0usize
        while row + 1usize < rows {
            let y0 = bounds.y + bounds.height * f32(row) / f32(rows - 1usize)
            let y1 = bounds.y + bounds.height * f32(row + 1usize) / f32(rows - 1usize)
            var col = 0usize
            while col + 1usize < columns {
                let x0 = bounds.x + bounds.width * f32(col) / f32(columns - 1usize)
                let x1 = bounds.x + bounds.width * f32(col + 1usize) / f32(columns - 1usize)
                let top_left = values[row * columns + col]
                let top_right = values[row * columns + col + 1usize]
                let bottom_right = values[(row + 1usize) * columns + col + 1usize]
                let bottom_left = values[(row + 1usize) * columns + col]
                let high0 = top_left >= level
                let high1 = top_right >= level
                let high2 = bottom_right >= level
                let high3 = bottom_left >= level
                var edges: [4]Coord = zero
                var hits: [4]bool = zero
                var count = 0usize
                if high0 != high1 {
                    let (p, crossing_error) = contour_cross(Coord { x: x0, y: y0 }, Coord { x: x1, y: y0 }, top_left, top_right, level)
                    if crossing_error != ok { ret (zero, crossing_error) }
                    edges[0usize] = p
                    hits[0usize] = true
                    count += 1usize
                }
                if high1 != high2 {
                    let (p, crossing_error) = contour_cross(Coord { x: x1, y: y0 }, Coord { x: x1, y: y1 }, top_right, bottom_right, level)
                    if crossing_error != ok { ret (zero, crossing_error) }
                    edges[1usize] = p
                    hits[1usize] = true
                    count += 1usize
                }
                if high2 != high3 {
                    let (p, crossing_error) = contour_cross(Coord { x: x1, y: y1 }, Coord { x: x0, y: y1 }, bottom_right, bottom_left, level)
                    if crossing_error != ok { ret (zero, crossing_error) }
                    edges[2usize] = p
                    hits[2usize] = true
                    count += 1usize
                }
                if high3 != high0 {
                    let (p, crossing_error) = contour_cross(Coord { x: x0, y: y1 }, Coord { x: x0, y: y0 }, bottom_left, top_left, level)
                    if crossing_error != ok { ret (zero, crossing_error) }
                    edges[3usize] = p
                    hits[3usize] = true
                    count += 1usize
                }
                if count == 2usize {
                    var first: Coord = zero
                    var last: Coord = zero
                    var found = 0usize
                    var edge = 0usize
                    while edge < 4usize {
                        if hits[edge] {
                            if found == 0usize { first = edges[edge] } else { last = edges[edge] }
                            found += 1usize
                        }
                        edge += 1usize
                    }
                    if first.x != last.x || first.y != last.y {
                        if used == segments.len { ret (zero, TooLarge) }
                        segments[used] = Segment { from: first, to: last }
                        used += 1usize
                    }
                } else if count == 4usize {
                    let center = top_left * 0.25f64 + top_right * 0.25f64 + bottom_right * 0.25f64 + bottom_left * 0.25f64
                    if !finite64(center) { ret (zero, Invalid) }
                    let a = 0usize
                    var b = 1usize
                    var c = 2usize
                    var d = 3usize
                    if (center >= level) != high0 {
                        b = 3usize
                        c = 1usize
                        d = 2usize
                    }
                    if segments.len - used < 2usize { ret (zero, TooLarge) }
                    segments[used] = Segment { from: edges[a], to: edges[b] }
                    segments[used + 1usize] = Segment { from: edges[c], to: edges[d] }
                    used += 2usize
                }
                col += 1usize
            }
            row += 1usize
        }
        layers[l] = Layout { kind: .Rug, coords: zero, segments: segments[start..used], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: f32(rows - 1usize) }
        l += 1usize
    }
    ret (layers[..levels.len], ok)
}

// Evaluate a normalized product-Gaussian KDE at regular domain coordinates,
// then contour at increasing fractions of the observed grid peak. The caller
// owns grid axes, density values, cutoffs and marching-squares storage.
fn density2d(x: []const f64, y: []const f64, x_min: f64, x_max: f64, y_min: f64, y_max: f64, bounds: geometry.Rect, bandwidth_x: f64, bandwidth_y: f64, fractions: []const f64, grid_x: []f64, grid_y: []f64, values: []f64, cutoffs: []f64, segments: []Segment, layers: []Layout) -> (Density2dLayout, err) {
    if x.len == 0usize || fractions.len == 0usize { ret (zero, Empty) }
    if x.len != y.len || !finite64(x_min) || !finite64(x_max) || !finite64(y_min) || !finite64(y_max) || x_max <= x_min || y_max <= y_min || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !(bandwidth_x > 0.0f64) || !(bandwidth_y > 0.0f64) || !finite64(bandwidth_x) || !finite64(bandwidth_y) || grid_x.len < 2usize || grid_y.len < 2usize { ret (zero, Invalid) }
    if grid_x.len > values.len / grid_y.len || cutoffs.len < fractions.len || layers.len < fractions.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < x.len {
        if !finite64(x[i]) || !finite64(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < fractions.len {
        if !finite64(fractions[i]) || !(fractions[i] > 0.0f64 && fractions[i] < 1.0f64) || (i > 0usize && fractions[i] <= fractions[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < grid_x.len {
        grid_x[i] = x_min + (x_max - x_min) * f64(i) / f64(grid_x.len - 1usize)
        i += 1usize
    }
    i = 0usize
    while i < grid_y.len {
        grid_y[i] = y_max - (y_max - y_min) * f64(i) / f64(grid_y.len - 1usize)
        i += 1usize
    }
    let needed = grid_x.len * grid_y.len
    let kde_error = stat.kde2d(x, y, bandwidth_x, bandwidth_y, grid_x, grid_y, values[..needed])
    if kde_error != ok { ret (zero, Invalid) }
    var peak = 0.0f64
    i = 0usize
    while i < needed {
        if !finite64(values[i]) || values[i] < 0.0f64 { ret (zero, Invalid) }
        if values[i] > peak { peak = values[i] }
        i += 1usize
    }
    if !(peak > 0.0f64) { ret (zero, Invalid) }
    i = 0usize
    while i < fractions.len {
        cutoffs[i] = peak * fractions[i]
        if !(cutoffs[i] > 0.0f64) || (i > 0usize && cutoffs[i] <= cutoffs[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let (lines, contour_error) = contour(values[..needed], grid_x.len, grid_y.len, cutoffs[..fractions.len], bounds, segments, layers)
    if contour_error != ok { ret (zero, contour_error) }
    ret (Density2dLayout { contours: lines, grid: values[..needed], cutoffs: cutoffs[..fractions.len], peak: peak }, ok)
}

fn contour_clip(vertices: []const ContourVertex, cutoff: f64, above: bool, out: []ContourVertex) -> (usize, err) {
    if vertices.len == 0usize { ret (0usize, ok) }
    var prior = vertices[vertices.len - 1usize]
    var prior_inside = prior.value >= cutoff
    if !above { prior_inside = prior.value <= cutoff }
    var used = 0usize
    var i = 0usize
    while i < vertices.len {
        let current = vertices[i]
        var inside = current.value >= cutoff
        if !above { inside = current.value <= cutoff }
        if inside != prior_inside {
            if used == out.len { ret (0usize, TooLarge) }
            let (point, crossing_error) = contour_cross(prior.point, current.point, prior.value, current.value, cutoff)
            if crossing_error != ok { ret (0usize, crossing_error) }
            out[used] = ContourVertex { point: point, value: cutoff }
            used += 1usize
        }
        if inside {
            if used == out.len { ret (0usize, TooLarge) }
            out[used] = current
            used += 1usize
        }
        prior = current
        prior_inside = inside
        i += 1usize
    }
    ret (used, ok)
}

// Split each grid cell into two piecewise-linear triangles, then clip each
// triangle to successive scalar bands and emit caller-owned Area polygons.
// ponytail: independent triangles grow with cells*bands; merge regions if size matters.
fn filled_contour(values: []const f64, columns: usize, rows: usize, levels: []const f64, bounds: geometry.Rect, points: []Coord, layers: []Layout, band_ids: []usize) -> ([]Layout, err) {
    if values.len == 0usize || levels.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || rows < 2usize || columns > values.len || values.len % columns != 0usize || values.len / columns != rows || !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) { ret (zero, Invalid) }
    var lo = values[0usize]
    var hi = lo
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) { ret (zero, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    if lo == hi { ret (zero, Invalid) }
    i = 0usize
    while i < levels.len {
        if !finite64(levels[i]) || levels[i] <= lo || levels[i] >= hi || (i > 0usize && levels[i] <= levels[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var used_points = 0usize
    var used_layers = 0usize
    var row = 0usize
    while row + 1usize < rows {
        let y0 = bounds.y + bounds.height * f32(row) / f32(rows - 1usize)
        let y1 = bounds.y + bounds.height * f32(row + 1usize) / f32(rows - 1usize)
        var col = 0usize
        while col + 1usize < columns {
            let x0 = bounds.x + bounds.width * f32(col) / f32(columns - 1usize)
            let x1 = bounds.x + bounds.width * f32(col + 1usize) / f32(columns - 1usize)
            let tl = ContourVertex { point: Coord { x: x0, y: y0 }, value: values[row * columns + col] }
            let tr = ContourVertex { point: Coord { x: x1, y: y0 }, value: values[row * columns + col + 1usize] }
            let br = ContourVertex { point: Coord { x: x1, y: y1 }, value: values[(row + 1usize) * columns + col + 1usize] }
            let bl = ContourVertex { point: Coord { x: x0, y: y1 }, value: values[(row + 1usize) * columns + col] }
            var triangle = [3]ContourVertex{ tl, tr, br }
            var part = 0usize
            while part < 2usize {
                if part == 1usize {
                    triangle[1usize] = br
                    triangle[2usize] = bl
                }
                var band_index = 0usize
                while band_index <= levels.len {
                    var lower = lo
                    if band_index > 0usize { lower = levels[band_index - 1usize] }
                    var upper = hi
                    if band_index < levels.len { upper = levels[band_index] }
                    var first: [8]ContourVertex = zero
                    var second: [8]ContourVertex = zero
                    let (lower_count, lower_error) = contour_clip(triangle[..], lower, true, first[..])
                    if lower_error != ok { ret (zero, lower_error) }
                    let (count, upper_error) = contour_clip(first[..lower_count], upper, false, second[..])
                    if upper_error != ok { ret (zero, upper_error) }
                    if count >= 3usize {
                        var twice_area = 0.0f64
                        i = 0usize
                        while i < count {
                            let next = (i + 1usize) % count
                            twice_area += f64(second[i].point.x) * f64(second[next].point.y) - f64(second[next].point.x) * f64(second[i].point.y)
                            i += 1usize
                        }
                        if twice_area < 0.0f64 { twice_area = 0.0f64 - twice_area }
                        if twice_area > 0.000001f64 {
                            if used_layers == layers.len || used_layers == band_ids.len || points.len - used_points < count + 1usize { ret (zero, TooLarge) }
                            let start = used_points
                            i = 0usize
                            while i < count {
                                points[used_points] = second[i].point
                                used_points += 1usize
                                i += 1usize
                            }
                            points[used_points] = second[0usize].point
                            used_points += 1usize
                            layers[used_layers] = Layout { kind: .Area, coords: points[start..used_points], segments: zero, bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: f32(rows - 1usize) }
                            band_ids[used_layers] = band_index
                            used_layers += 1usize
                        }
                    }
                    band_index += 1usize
                }
                part += 1usize
            }
            col += 1usize
        }
        row += 1usize
    }
    ret (layers[..used_layers], ok)
}

// Monday is row zero. Missing offsets emit no tile, preserving a visible gap.
fn calendar_heatmap(days: []const CalendarDay, day_count: usize, first_weekday: usize, bounds: geometry.Rect, gap: f32, cells: []Cell) -> (MatrixLayout, err) {
    if days.len == 0usize { ret (zero, Empty) }
    if day_count == 0usize || day_count > 366usize || first_weekday >= 7usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if cells.len < days.len { ret (zero, TooLarge) }
    let columns = (first_weekday + day_count + 6usize) / 7usize
    var lo = days[0usize].value
    var hi = lo
    var i = 0usize
    while i < days.len {
        let d = days[i]
        if d.offset >= day_count || (i > 0usize && d.offset <= days[i - 1usize].offset) || !finite64(d.value) || !finite(f32(d.value)) { ret (zero, Invalid) }
        if d.value < lo { lo = d.value }
        if d.value > hi { hi = d.value }
        let slot = first_weekday + d.offset
        let tile = cell_rect(bounds, slot / 7usize, slot % 7usize, columns, 7usize)
        if tile.width <= gap || tile.height <= gap { ret (zero, Invalid) }
        cells[i] = Cell { rect: geometry.rect(tile.x + gap * 0.5, tile.y + gap * 0.5, tile.width - gap, tile.height - gap), value: f32(d.value) }
        i += 1usize
    }
    if !finite(f32(hi - lo)) { ret (zero, Invalid) }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..days.len], columns: columns, rows: 7usize, value_min: f32(lo), value_max: f32(hi) }, ok)
}

// Observations are row-major. Pearson's r comes from e.algo.stat; two scratch
// columns and the output cells belong to the caller. Constant columns refuse.
fn correlation_matrix(observations: []const f64, columns: usize, bounds: geometry.Rect, x: []f64, y: []f64, cells: []Cell) -> (MatrixLayout, err) {
    if observations.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    let rows = observations.len / columns
    if rows < 2usize { ret (zero, Invalid) }
    if cells.len / columns < columns || x.len < rows || y.len < rows { ret (zero, TooLarge) }
    var i = 0usize
    while i < observations.len {
        if !finite64(observations[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var row = 0usize
    while row < columns {
        var column = 0usize
        while column < columns {
            i = 0usize
            while i < rows {
                x[i] = observations[i * columns + column]
                y[i] = observations[i * columns + row]
                i += 1usize
            }
            let (coefficient, defined) = stat.correlation_pearson(x[..rows], y[..rows])
            if !defined || !finite(f32(coefficient)) { ret (zero, Invalid) }
            var value = f32(coefficient)
            if value < -1.0 { value = -1.0 }
            if value > 1.0 { value = 1.0 }
            cells[row * columns + column] = Cell { rect: cell_rect(bounds, column, row, columns, columns), value: value }
            column += 1usize
        }
        row += 1usize
    }
    ret (MatrixLayout { kind: .Correlation, cells: cells[..columns * columns], columns: columns, rows: columns, value_min: -1.0, value_max: 1.0 }, ok)
}

// Each row crosses one independently normalized vertical axis per column.
fn parallel_coordinates(observations: []const f64, columns: usize, bounds: geometry.Rect, minimums: []f64, maximums: []f64, lines: []Segment, axes: []Segment) -> (Layout, Layout, err) {
    if observations.len == 0usize { ret (zero, zero, Empty) }
    if columns < 2usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    let rows = observations.len / columns
    if minimums.len < columns || maximums.len < columns || axes.len < columns || lines.len / (columns - 1usize) < rows { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < observations.len {
        if !finite64(observations[i]) { ret (zero, zero, Invalid) }
        i += 1usize
    }
    var column = 0usize
    while column < columns {
        minimums[column] = observations[column]
        maximums[column] = observations[column]
        i = 1usize
        while i < rows {
            let value = observations[i * columns + column]
            if value < minimums[column] { minimums[column] = value }
            if value > maximums[column] { maximums[column] = value }
            i += 1usize
        }
        if !finite64(maximums[column] - minimums[column]) { ret (zero, zero, Invalid) }
        let x = bounds.x + bounds.width * f32(column) / f32(columns - 1usize)
        axes[column] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
        column += 1usize
    }
    var row = 0usize
    while row < rows {
        column = 0usize
        while column + 1usize < columns {
            var first = 0.5f64
            var second = 0.5f64
            if maximums[column] > minimums[column] { first = (observations[row * columns + column] - minimums[column]) / (maximums[column] - minimums[column]) }
            if maximums[column + 1usize] > minimums[column + 1usize] { second = (observations[row * columns + column + 1usize] - minimums[column + 1usize]) / (maximums[column + 1usize] - minimums[column + 1usize]) }
            if !finite64(first) || !finite64(second) { ret (zero, zero, Invalid) }
            let left = bounds.x + bounds.width * f32(column) / f32(columns - 1usize)
            let right = bounds.x + bounds.width * f32(column + 1usize) / f32(columns - 1usize)
            lines[row * (columns - 1usize) + column] = Segment {
                from: Coord { x: left, y: bounds.y + bounds.height * (1.0 - f32(first)) },
                to: Coord { x: right, y: bounds.y + bounds.height * (1.0 - f32(second)) },
            }
            column += 1usize
        }
        row += 1usize
    }
    let data = Layout { kind: .Rug, coords: zero, segments: lines[..rows * (columns - 1usize)], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: 1.0 }
    let guides = Layout { kind: .Rug, coords: zero, segments: axes[..columns], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: 1.0 }
    ret (data, guides, ok)
}

// Off-diagonal cells plot every variable pair; callers label the blank diagonal.
// Inputs are row-major and each variable keeps one range across its panels.
fn scatterplot_matrix(observations: []const f64, columns: usize, bounds: geometry.Rect, gap: f32, minimums: []f64, maximums: []f64, panels: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if observations.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    let rows = observations.len / columns
    if minimums.len < columns || maximums.len < columns || panels.len / columns < columns || layers.len / columns < columns { ret (zero, TooLarge) }
    let count = columns * columns
    if points.len / (count - columns) < rows { ret (zero, TooLarge) }
    let (_, panel_error) = facet_grid(bounds, columns, count, gap, panels)
    if panel_error != ok { ret (zero, panel_error) }
    var column = 0usize
    while column < columns {
        minimums[column] = observations[column]
        maximums[column] = observations[column]
        var row = 0usize
        while row < rows {
            let value = observations[row * columns + column]
            if !finite64(value) || !finite(f32(value)) { ret (zero, Invalid) }
            if value < minimums[column] { minimums[column] = value }
            if value > maximums[column] { maximums[column] = value }
            row += 1usize
        }
        if !finite64(maximums[column] - minimums[column]) { ret (zero, Invalid) }
        column += 1usize
    }
    var used = 0usize
    var panel = 0usize
    while panel < count {
        let x_column = panel % columns
        let y_column = panel / columns
        let first = used
        if x_column != y_column {
            var row = 0usize
            while row < rows {
                var x = 0.5f64
                var y = 0.5f64
                if maximums[x_column] > minimums[x_column] { x = (observations[row * columns + x_column] - minimums[x_column]) / (maximums[x_column] - minimums[x_column]) }
                if maximums[y_column] > minimums[y_column] { y = (observations[row * columns + y_column] - minimums[y_column]) / (maximums[y_column] - minimums[y_column]) }
                if !finite64(x) || !finite64(y) { ret (zero, Invalid) }
                points[used] = Coord {
                    x: panels[panel].x + panels[panel].width * f32(x),
                    y: panels[panel].y + panels[panel].height * f32(1.0f64 - y),
                }
                used += 1usize
                row += 1usize
            }
        }
        layers[panel] = Layout { kind: .Scatter, coords: points[first..used], segments: zero, bars: zero, x_min: f32(minimums[x_column]), x_max: f32(maximums[x_column]), y_min: f32(minimums[y_column]), y_max: f32(maximums[y_column]) }
        panel += 1usize
    }
    ret (layers[..count], ok)
}

// Row-major equal panels for a later facet mapping stage. All panels use the
// same outer bounds; callers choose shared or independent data scales.
fn facet_grid(bounds: geometry.Rect, columns: usize, count: usize, gap: f32, panels: []geometry.Rect) -> ([]geometry.Rect, err) {
    if columns == 0usize || count == 0usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if panels.len < count { ret (zero, TooLarge) }
    var rows = count / columns
    if count % columns != 0usize { rows += 1usize }
    let width = (bounds.width - gap * f32(columns - 1usize)) / f32(columns)
    let height = (bounds.height - gap * f32(rows - 1usize)) / f32(rows)
    if !(width > 0.0) || !(height > 0.0) { ret (zero, Invalid) }
    var i = 0usize
    while i < count {
        panels[i] = geometry.rect(bounds.x + f32(i % columns) * (width + gap), bounds.y + f32(i / columns) * (height + gap), width, height)
        i += 1usize
    }
    ret (panels[..count], ok)
}

// Arrange independent plots in a weighted, row-major grid. Unlike facets,
// each returned rectangle may host a different mark kind and data domain.
// Caller owns the output and reserves any per-plot title/axis margins.
fn plot_grid(bounds: geometry.Rect, column_weights: []const f32, row_weights: []const f32, gap_x: f32, gap_y: f32, panels: []geometry.Rect) -> ([]geometry.Rect, err) {
    if column_weights.len == 0usize || row_weights.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(bounds.x + bounds.width) || !finite(bounds.y + bounds.height) || !finite(gap_x) || !finite(gap_y) || gap_x < 0.0 || gap_y < 0.0 { ret (zero, Invalid) }
    if panels.len / column_weights.len < row_weights.len { ret (zero, TooLarge) }
    let horizontal_gaps = gap_x * f32(column_weights.len - 1usize)
    let vertical_gaps = gap_y * f32(row_weights.len - 1usize)
    let available_width = bounds.width - horizontal_gaps
    let available_height = bounds.height - vertical_gaps
    if !finite(available_width) || !finite(available_height) || available_width <= 0.0 || available_height <= 0.0 { ret (zero, Invalid) }
    var total_width = 0.0f64
    var total_height = 0.0f64
    var column = 0usize
    while column < column_weights.len {
        let weight = column_weights[column]
        if !finite(weight) || weight <= 0.0 { ret (zero, Invalid) }
        total_width += f64(weight)
        column += 1usize
    }
    var row = 0usize
    while row < row_weights.len {
        let weight = row_weights[row]
        if !finite(weight) || weight <= 0.0 { ret (zero, Invalid) }
        total_height += f64(weight)
        row += 1usize
    }
    if !finite64(total_width) || !finite64(total_height) { ret (zero, Invalid) }
    column = 0usize
    while column < column_weights.len {
        let width = available_width * f32(f64(column_weights[column]) / total_width)
        if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
        column += 1usize
    }
    row = 0usize
    while row < row_weights.len {
        let height = available_height * f32(f64(row_weights[row]) / total_height)
        if !finite(height) || height <= 0.0 { ret (zero, Invalid) }
        row += 1usize
    }
    let right = bounds.x + bounds.width
    let bottom = bounds.y + bounds.height
    var y = bounds.y
    row = 0usize
    while row < row_weights.len {
        var height = available_height * f32(f64(row_weights[row]) / total_height)
        if row + 1usize == row_weights.len { height = bottom - y }
        if !finite(height) || height <= 0.0 { ret (zero, Invalid) }
        var x = bounds.x
        column = 0usize
        while column < column_weights.len {
            var width = available_width * f32(f64(column_weights[column]) / total_width)
            if column + 1usize == column_weights.len { width = right - x }
            if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
            panels[row * column_weights.len + column] = geometry.rect(x, y, width, height)
            x += width + gap_x
            column += 1usize
        }
        y += height + gap_y
        row += 1usize
    }
    ret (panels[..column_weights.len * row_weights.len], ok)
}

// Shared-scale facet ticks are drawn in every panel, but their text belongs
// only on the exterior: x labels beneath the last row, y labels at the first
// column. Panels must form a complete, aligned row-major rectangle.
fn shared_facet_guide_labels(panels: []const geometry.Rect, columns: usize, x_ticks: []const Tick, x_text: []const str, y_ticks: []const Tick, y_text: []const str, size: f32, out: []Label) -> ([]Label, err) {
    if panels.len == 0usize || columns == 0usize || panels.len % columns != 0usize || x_ticks.len != x_text.len || y_ticks.len != y_text.len || !finite(size) || size <= 0.0 { ret (zero, Invalid) }
    let rows = panels.len / columns
    var i = 0usize
    while i < panels.len {
        let panel = panels[i]
        if !valid_bounds(panel) || !finite(panel.x + panel.width) || !finite(panel.y + panel.height) { ret (zero, Invalid) }
        if i % columns > 0usize {
            let before = panels[i - 1usize]
            if panel.x < before.x + before.width || panel.y != before.y || panel.height != before.height { ret (zero, Invalid) }
        }
        if i >= columns {
            let above = panels[i - columns]
            if panel.y < above.y + above.height || panel.x != above.x || panel.width != above.width { ret (zero, Invalid) }
        }
        i += 1usize
    }
    if x_ticks.len > 0usize && out.len / x_ticks.len < columns { ret (zero, TooLarge) }
    let x_count = columns * x_ticks.len
    if y_ticks.len > 0usize && (out.len - x_count) / y_ticks.len < rows { ret (zero, TooLarge) }
    var used = 0usize
    var column = 0usize
    while column < columns {
        let panel = panels[(rows - 1usize) * columns + column]
        let (labels, label_error) = guide_labels(panel, x_ticks, x_text, y_ticks[..0usize], y_text[..0usize], size, out[used..])
        if label_error != ok { ret (zero, label_error) }
        used += labels.len
        column += 1usize
    }
    var row = 0usize
    while row < rows {
        let panel = panels[row * columns]
        let (labels, label_error) = guide_labels(panel, x_ticks[..0usize], x_text[..0usize], y_ticks, y_text, size, out[used..])
        if label_error != ok { ret (zero, label_error) }
        used += labels.len
        row += 1usize
    }
    ret (out[..used], ok)
}

// One category key selects one panel. Levels fix row-major panel order and
// reserve empty panels; all Scatter marks share the caller's x/y domains.
fn category_facet_scatter(keys: []const str, x: []const f32, y: []const f32, levels: []const str, bounds: geometry.Rect, columns: usize, gap: f32, strip_height: f32, x_min: f32, x_max: f32, y_min: f32, y_max: f32, panels: []geometry.Rect, points: []Coord, marks: []Layout, strips: []Label, counts: []usize) -> (CategoryFacetLayout, err) {
    if keys.len == 0usize || levels.len == 0usize { ret (zero, Empty) }
    if x.len != keys.len || y.len != keys.len || !valid_bounds(bounds) || !finite(strip_height) || strip_height <= 0.0 || !finite(x_min) || !finite(x_max) || !finite(y_min) || !finite(y_max) || x_max <= x_min || y_max <= y_min || !finite(x_max - x_min) || !finite(y_max - y_min) { ret (zero, Invalid) }
    let n = levels.len
    if panels.len < n || points.len < keys.len || marks.len < n || strips.len < n || counts.len < n { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        let label = Label { text: levels[i], anchor: Coord { x: bounds.x, y: bounds.y }, align: .Center }
        if !valid_label(&label) { ret (zero, Invalid) }
        var j = 0usize
        while j < i {
            if str.eq(levels[i], levels[j]) { ret (zero, Invalid) }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < keys.len {
        if !finite(x[i]) || !finite(y[i]) || x[i] < x_min || x[i] > x_max || y[i] < y_min || y[i] > y_max { ret (zero, Invalid) }
        var found = false
        var j = 0usize
        while j < n {
            if str.eq(keys[i], levels[j]) {
                found = true
                break
            }
            j += 1usize
        }
        if !found { ret (zero, Invalid) }
        i += 1usize
    }
    let (placed, panel_error) = facet_grid(bounds, columns, n, gap, panels)
    if panel_error != ok { ret (zero, panel_error) }
    var used = 0usize
    i = 0usize
    while i < n {
        let panel = placed[i]
        let plot = geometry.rect(panel.x + 5.0, panel.y + strip_height, panel.width - 10.0, panel.height - strip_height - 5.0)
        if !valid_bounds(plot) { ret (zero, TooLarge) }
        strips[i] = Label { text: levels[i], anchor: Coord { x: panel.x + panel.width * 0.5, y: panel.y + strip_height * 0.70 }, align: .Center }
        let first = used
        var j = 0usize
        while j < keys.len {
            if str.eq(keys[j], levels[i]) {
                points[used] = Coord {
                    x: plot.x + plot.width * ((x[j] - x_min) / (x_max - x_min)),
                    y: plot.y + plot.height * (1.0 - (y[j] - y_min) / (y_max - y_min)),
                }
                if !finite(points[used].x) || !finite(points[used].y) { ret (zero, Invalid) }
                used += 1usize
            }
            j += 1usize
        }
        counts[i] = used - first
        marks[i] = Layout { kind: .Scatter, coords: points[first..used], segments: zero, bars: zero, x_min: x_min, x_max: x_max, y_min: y_min, y_max: y_max }
        i += 1usize
    }
    ret (CategoryFacetLayout { panels: panels[..n], marks: marks[..n], strips: strips[..n], counts: counts[..n] }, ok)
}

// Node-link layout of an undirected graph by Fruchterman and Reingold (1991):
// nodes repel with k^2/d and linked nodes attract with d^2/k in a unit square
// (k = sqrt(1/n)), each step moving a node at most the temperature, which
// cools linearly from 0.1 to 0. Nodes start on a golden-angle spiral, so the
// result is deterministic and a symmetric start cannot trap it. The finished
// positions are scaled uniformly into `bounds`, keeping the aspect ratio.
// `work` holds 4 * node_count values; `links` is a Rug layout of one segment
// per edge that is not a self-loop, for the scene and SVG adapters.
// ponytail: all-pairs repulsion, O(n^2) per step; Barnes-Hut when graphs pass
// a few thousand nodes.
fn network_layout(node_count: usize, from: []const u32, to: []const u32, bounds: geometry.Rect, iterations: usize, work: []f64, nodes: []Coord, segments: []Segment) -> (NetworkLayout, err) {
    if node_count == 0usize { ret (zero, Empty) }
    if from.len != to.len || !valid_bounds(bounds) || iterations > 100000usize { ret (zero, Invalid) }
    if work.len < 4usize * node_count || nodes.len < node_count { ret (zero, TooLarge) }
    var links = 0usize
    var e = 0usize
    while e < from.len {
        if usize(from[e]) >= node_count || usize(to[e]) >= node_count { ret (zero, Invalid) }
        if from[e] != to[e] { links += 1usize }
        e += 1usize
    }
    if segments.len < links { ret (zero, TooLarge) }
    let n = node_count
    let k = math.sqrt[f64](1.0f64 / f64(n))
    var i = 0usize
    while i < n {
        let radius = 0.45f64 * math.sqrt[f64]((f64(i) + 0.5f64) / f64(n))
        let angle = f64(i) * 2.399963229728653f64
        work[2usize * i] = 0.5f64 + radius * math.cos[f64](angle)
        work[2usize * i + 1usize] = 0.5f64 + radius * math.sin[f64](angle)
        i += 1usize
    }
    var step = 0usize
    while step < iterations {
        let temperature = 0.1f64 * (1.0f64 - f64(step) / f64(iterations))
        i = 0usize
        while i < 2usize * n {
            work[2usize * n + i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i < n {
            var j = i + 1usize
            while j < n {
                let dx = work[2usize * i] - work[2usize * j]
                let dy = work[2usize * i + 1usize] - work[2usize * j + 1usize]
                var d = math.sqrt[f64](dx * dx + dy * dy)
                if d < 0.000000001f64 { d = 0.000000001f64 }
                let f = k * k / d / d
                work[2usize * n + 2usize * i] += dx * f
                work[2usize * n + 2usize * i + 1usize] += dy * f
                work[2usize * n + 2usize * j] -= dx * f
                work[2usize * n + 2usize * j + 1usize] -= dy * f
                j += 1usize
            }
            i += 1usize
        }
        e = 0usize
        while e < from.len {
            let u = usize(from[e])
            let v = usize(to[e])
            if u != v {
                let dx = work[2usize * u] - work[2usize * v]
                let dy = work[2usize * u + 1usize] - work[2usize * v + 1usize]
                let d = math.sqrt[f64](dx * dx + dy * dy)
                let f = d / k
                work[2usize * n + 2usize * u] -= dx * f
                work[2usize * n + 2usize * u + 1usize] -= dy * f
                work[2usize * n + 2usize * v] += dx * f
                work[2usize * n + 2usize * v + 1usize] += dy * f
            }
            e += 1usize
        }
        i = 0usize
        while i < n {
            let dx = work[2usize * n + 2usize * i]
            let dy = work[2usize * n + 2usize * i + 1usize]
            let length = math.sqrt[f64](dx * dx + dy * dy)
            if length > 0.0f64 {
                var limited = length
                if limited > temperature { limited = temperature }
                work[2usize * i] += dx / length * limited
                work[2usize * i + 1usize] += dy / length * limited
            }
            i += 1usize
        }
        step += 1usize
    }
    var min_x = work[0usize]
    var max_x = work[0usize]
    var min_y = work[1usize]
    var max_y = work[1usize]
    i = 1usize
    while i < n {
        if work[2usize * i] < min_x { min_x = work[2usize * i] }
        if work[2usize * i] > max_x { max_x = work[2usize * i] }
        if work[2usize * i + 1usize] < min_y { min_y = work[2usize * i + 1usize] }
        if work[2usize * i + 1usize] > max_y { max_y = work[2usize * i + 1usize] }
        i += 1usize
    }
    var span = max_x - min_x
    if max_y - min_y > span * f64(bounds.height) / f64(bounds.width) { span = (max_y - min_y) * f64(bounds.width) / f64(bounds.height) }
    var scale = 0.0f64
    if span > 0.0f64 { scale = f64(bounds.width) / span }
    let center_x = (min_x + max_x) / 2.0f64
    let center_y = (min_y + max_y) / 2.0f64
    i = 0usize
    while i < n {
        nodes[i] = Coord { x: bounds.x + bounds.width / 2.0 + f32((work[2usize * i] - center_x) * scale), y: bounds.y + bounds.height / 2.0 + f32((work[2usize * i + 1usize] - center_y) * scale) }
        if !finite(nodes[i].x) || !finite(nodes[i].y) { ret (zero, Invalid) }
        i += 1usize
    }
    var s = 0usize
    e = 0usize
    while e < from.len {
        if from[e] != to[e] {
            segments[s] = Segment { from: nodes[usize(from[e])], to: nodes[usize(to[e])] }
            s += 1usize
        }
        e += 1usize
    }
    let link_layout = Layout { kind: .Rug, coords: zero, segments: segments[..s], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (NetworkLayout { nodes: nodes[..n], links: link_layout }, ok)
}

// Each node's place in its row as a fraction, ordered by its key in
// `work[2n..3n)`, then by its old place in `work[n..2n)`, then by index; rows are
// `work[0..n)`.
fn place_rows(n: usize, work: []f64) {
    var i = 0usize
    while i < n {
        var rank = 0usize
        var size = 0usize
        var j = 0usize
        while j < n {
            if work[j] == work[i] {
                size += 1usize
                let kj = work[2usize * n + j]
                let ki = work[2usize * n + i]
                if kj < ki || (kj == ki && (work[n + j] < work[n + i] || (work[n + j] == work[n + i] && j < i))) { rank += 1usize }
            }
            j += 1usize
        }
        work[3usize * n + i] = (f64(rank) + 0.5f64) / f64(size)
        i += 1usize
    }
    i = 0usize
    while i < n {
        work[n + i] = work[3usize * n + i]
        i += 1usize
    }
}

// A directed acyclic graph in rows (D2117), after Sugiyama, Tagawa and Toda
// (1981): a node's row is its longest path from a source, so every link points
// down. Nodes start in index order within their row, and `sweeps` alternating
// passes (down, then up) reorder every row by the mean place of each node's
// predecessors, then successors, to cut crossings; a node with none keeps its
// place. Rows split `bounds` evenly top to bottom, and nodes split their row
// evenly left to right. A cycle is Invalid and self-loops are ignored. `work`
// holds 4 * node_count values; `links` is a Rug layout of one straight segment
// per edge that is not a self-loop.
// ponytail: O(n^2) ranking and O(n * edges) passes suit the hundreds of nodes a
// readable hierarchy has; edges spanning rows get no dummy nodes, so they may
// pass through nodes in the rows between.
fn layered_layout(node_count: usize, from: []const u32, to: []const u32, bounds: geometry.Rect, sweeps: usize, work: []f64, nodes: []Coord, segments: []Segment) -> (NetworkLayout, err) {
    if node_count == 0usize { ret (zero, Empty) }
    if from.len != to.len || !valid_bounds(bounds) || sweeps > 1000usize { ret (zero, Invalid) }
    if work.len < 4usize * node_count || nodes.len < node_count { ret (zero, TooLarge) }
    var links = 0usize
    var e = 0usize
    while e < from.len {
        if usize(from[e]) >= node_count || usize(to[e]) >= node_count { ret (zero, Invalid) }
        if from[e] != to[e] { links += 1usize }
        e += 1usize
    }
    if segments.len < links { ret (zero, TooLarge) }
    let n = node_count
    // Rows by relaxing every link until none moves; a row reaching n is a cycle.
    var i = 0usize
    while i < n {
        work[i] = 0.0f64
        work[n + i] = 0.0f64
        work[2usize * n + i] = f64(i)
        i += 1usize
    }
    var rows = 1usize
    var moved = true
    while moved {
        moved = false
        e = 0usize
        while e < from.len {
            let u = usize(from[e])
            let v = usize(to[e])
            if u != v && work[v] < work[u] + 1.0f64 {
                work[v] = work[u] + 1.0f64
                if work[v] >= f64(n) { ret (zero, Invalid) }
                if usize(work[v]) + 1usize > rows { rows = usize(work[v]) + 1usize }
                moved = true
            }
            e += 1usize
        }
    }
    place_rows(n, work)
    var sweep = 0usize
    while sweep < sweeps {
        let downward = sweep % 2usize == 0usize
        i = 0usize
        while i < n {
            var total = 0.0f64
            var count = 0usize
            e = 0usize
            while e < from.len {
                let u = usize(from[e])
                let v = usize(to[e])
                if u != v && downward && v == i {
                    total += work[n + u]
                    count += 1usize
                }
                if u != v && !downward && u == i {
                    total += work[n + v]
                    count += 1usize
                }
                e += 1usize
            }
            work[2usize * n + i] = work[n + i]
            if count > 0usize { work[2usize * n + i] = total / f64(count) }
            i += 1usize
        }
        place_rows(n, work)
        sweep += 1usize
    }
    i = 0usize
    while i < n {
        nodes[i] = Coord { x: bounds.x + bounds.width * f32(work[n + i]), y: bounds.y + bounds.height * f32((work[i] + 0.5f64) / f64(rows)) }
        i += 1usize
    }
    var s = 0usize
    e = 0usize
    while e < from.len {
        if from[e] != to[e] {
            segments[s] = Segment { from: nodes[usize(from[e])], to: nodes[usize(to[e])] }
            s += 1usize
        }
        e += 1usize
    }
    let link_layout = Layout { kind: .Rug, coords: zero, segments: segments[..s], bars: zero, x_min: bounds.x, x_max: bounds.x + bounds.width, y_min: bounds.y, y_max: bounds.y + bounds.height }
    ret (NetworkLayout { nodes: nodes[..n], links: link_layout }, ok)
}
