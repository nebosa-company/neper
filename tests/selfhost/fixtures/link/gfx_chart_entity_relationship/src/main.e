use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let tables = [3]chart.EntityTable{
        chart.EntityTable { name: "Customer", center: chart.Coord { x: 60.0, y: 136.0 } },
        chart.EntityTable { name: "Order", center: chart.Coord { x: 180.0, y: 136.0 } },
        chart.EntityTable { name: "LineItem", center: chart.Coord { x: 300.0, y: 136.0 } },
    }
    let fields = [9]chart.EntityField{
        chart.EntityField { table: 0usize, name: "id", key: .Primary },
        chart.EntityField { table: 1usize, name: "id", key: .Primary },
        chart.EntityField { table: 2usize, name: "id", key: .Primary },
        chart.EntityField { table: 0usize, name: "name", key: .None },
        chart.EntityField { table: 1usize, name: "cust_id", key: .Foreign },
        chart.EntityField { table: 2usize, name: "order_id", key: .Foreign },
        chart.EntityField { table: 0usize, name: "email", key: .None },
        chart.EntityField { table: 1usize, name: "total", key: .None },
        chart.EntityField { table: 2usize, name: "qty", key: .None },
    }
    let relations = [2]chart.EntityRelation{
        chart.EntityRelation { from: 0usize, to: 1usize, from_card: .One, to_card: .ZeroMany, name: "places" },
        chart.EntityRelation { from: 1usize, to: 2usize, from_card: .One, to_card: .Many, name: "contains" },
    }
    let bounds = geometry.rect(12.0, 52.0, 336.0, 166.0)
    var boxes: [3]geometry.Rect = zero
    var headers: [3]geometry.Rect = zero
    var counts: [3]usize = zero
    var used: [3]usize = zero
    var table_labels: [3]chart.Label = zero
    var field_labels: [9]chart.Label = zero
    var key_labels: [9]chart.Label = zero
    var relation_labels: [2]chart.Label = zero
    var segments: [48]chart.Segment = zero
    let (diagram, result) = chart.entity_relationship(tables[..], fields[..], relations[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    if result != ok || diagram.tables.bars.len != 3usize || diagram.headers.bars.len != 3usize || diagram.connectors.segments.len != 20usize || diagram.table_labels.len != 3usize || diagram.field_labels.len != 9usize || diagram.key_labels.len != 5usize || diagram.relation_labels.len != 2usize { ret chart.Invalid }
    if counts[0usize] != 3usize || counts[1usize] != 3usize || counts[2usize] != 3usize || used[0usize] != 3usize || used[1usize] != 3usize || used[2usize] != 3usize { ret chart.Invalid }
    if field_labels[0usize].anchor.y != field_labels[1usize].anchor.y || field_labels[0usize].anchor.y >= field_labels[3usize].anchor.y || field_labels[3usize].anchor.y >= field_labels[6usize].anchor.y || boxes[0usize].x >= boxes[1usize].x || boxes[1usize].x >= boxes[2usize].x || !str.contains(key_labels[0usize].text, "PK") || !str.contains(key_labels[4usize].text, "FK") { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &diagram.tables, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &diagram.headers, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &diagram.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 26usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 250.0, "ER diagram", "Tables and cardinalities")
    try chart_svg.append(&writer, &diagram.tables, ink)
    try chart_svg.append(&writer, &diagram.headers, ink)
    try chart_svg.append(&writer, &diagram.connectors, ink)
    try chart_svg.append_labels(&writer, diagram.table_labels, ink, 8.0)
    try chart_svg.append_labels(&writer, diagram.field_labels, ink, 7.0)
    try chart_svg.append_labels(&writer, diagram.key_labels, ink, 7.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "Customer") || !str.contains(svg, "PK") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let reverse = [1]chart.EntityRelation{ chart.EntityRelation { from: 2usize, to: 1usize, from_card: .Many, to_card: .One, name: "belongs" } }
    let optional = [1]chart.EntityRelation{ chart.EntityRelation { from: 0usize, to: 1usize, from_card: .ZeroOne, to_card: .ZeroOne, name: "optional" } }
    let bad_field = [1]chart.EntityField{ chart.EntityField { table: 3usize, name: "bad", key: .None } }
    let bad_relation = [1]chart.EntityRelation{ chart.EntityRelation { from: 0usize, to: 3usize, from_card: .One, to_card: .Many, name: "bad" } }
    let self_relation = [1]chart.EntityRelation{ chart.EntityRelation { from: 0usize, to: 0usize, from_card: .One, to_card: .Many, name: "bad" } }
    let overlaps = [2]chart.EntityTable{ tables[0usize], tables[0usize] }
    let crowded = [2]chart.EntityTable{ tables[0usize], chart.EntityTable { name: "Near", center: chart.Coord { x: 158.0, y: 136.0 } } }
    let (_, reverse_error) = chart.entity_relationship(tables[..], fields[..], reverse[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (optional_layout, optional_error) = chart.entity_relationship(tables[..], fields[..], optional[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, empty_error) = chart.entity_relationship(tables[..0usize], fields[..0usize], relations[..0usize], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, field_error) = chart.entity_relationship(tables[..], bad_field[..], relations[..0usize], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, relation_error) = chart.entity_relationship(tables[..], fields[..], bad_relation[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, self_error) = chart.entity_relationship(tables[..], fields[..], self_relation[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, overlap_error) = chart.entity_relationship(overlaps[..], fields[..0usize], relations[..0usize], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, gap_error) = chart.entity_relationship(crowded[..], fields[..0usize], optional[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, bounds_error) = chart.entity_relationship(tables[..], fields[..], relations[..], geometry.rect(0.0, 0.0, -1.0, 166.0), 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, width_error) = chart.entity_relationship(tables[..], fields[..], relations[..], bounds, 50.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, box_error) = chart.entity_relationship(tables[..], fields[..], relations[..], bounds, 72.0, boxes[..2usize], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..])
    let (_, line_error) = chart.entity_relationship(tables[..], fields[..], relations[..], bounds, 72.0, boxes[..], headers[..], counts[..], used[..], table_labels[..], field_labels[..], key_labels[..], relation_labels[..], segments[..47usize])
    if reverse_error != ok || optional_error != ok || optional_layout.connectors.segments.len != 21usize || empty_error != chart.Empty || field_error != chart.Invalid || relation_error != chart.Invalid || self_error != chart.Invalid || overlap_error != chart.Invalid || gap_error != chart.TooLarge || bounds_error != chart.Invalid || width_error != chart.Invalid || box_error != chart.TooLarge || line_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart entity relationship ok\n")
    ret ok
}
