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
    let participants = [3]str{ "Client", "API", "DB" }
    let messages = [6]chart.SequenceMessage{
        chart.SequenceMessage { from: 0usize, to: 1usize, kind: .Call, text: "request" },
        chart.SequenceMessage { from: 1usize, to: 1usize, kind: .Call, text: "auth" },
        chart.SequenceMessage { from: 1usize, to: 2usize, kind: .Call, text: "lookup" },
        chart.SequenceMessage { from: 2usize, to: 1usize, kind: .Return, text: "row" },
        chart.SequenceMessage { from: 1usize, to: 0usize, kind: .Return, text: "200 OK" },
        chart.SequenceMessage { from: 0usize, to: 1usize, kind: .Async, text: "refresh" },
    }
    let activations = [2]chart.SequenceActivation{
        chart.SequenceActivation { participant: 1usize, first: 0usize, last: 4usize },
        chart.SequenceActivation { participant: 2usize, first: 2usize, last: 3usize },
    }
    let bounds = geometry.rect(16.0, 48.0, 328.0, 171.0)
    var headers: [3]geometry.Rect = zero
    var lifelines: [30]chart.Segment = zero
    var active: [2]geometry.Rect = zero
    var strokes: [48]chart.Segment = zero
    var layers: [6]chart.Layout = zero
    var labels: [6]chart.Label = zero
    let (diagram, result) = chart.sequence_diagram(participants[..], messages[..], activations[..], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    if result != ok || diagram.headers.bars.len != 3usize || diagram.lifelines.segments.len != 30usize || diagram.activations.bars.len != 2usize || diagram.messages.len != 6usize || diagram.labels.len != 6usize { ret chart.Invalid }
    if headers[0usize].x >= headers[1usize].x || headers[1usize].x >= headers[2usize].x || active[0usize].height <= active[1usize].height || diagram.messages[1usize].segments.len != 5usize || diagram.messages[3usize].segments.len != 6usize || diagram.messages[4usize].segments.len != 6usize || !str.contains(labels[1usize].text, "auth") { ret chart.Invalid }
    if diagram.messages[0usize].segments[0usize].from.y >= diagram.messages[1usize].segments[0usize].from.y || diagram.messages[1usize].segments[0usize].from.y >= diagram.messages[2usize].segments[0usize].from.y || diagram.messages[3usize].segments[0usize].from.x <= diagram.messages[3usize].segments[0usize].to.x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &diagram.headers, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &diagram.lifelines, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &diagram.activations, paint.Brush { Solid: ink })
    var i = 0usize
    while i < diagram.messages.len {
        try chart_scene.append(a, &builder, &diagram.messages[i], paint.Brush { Solid: ink })
        i += 1usize
    }
    if scene.builder_count(&builder) != 61usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 250.0, "Sequence diagram", "Ordered messages")
    try chart_svg.append(&writer, &diagram.headers, ink)
    try chart_svg.append(&writer, &diagram.lifelines, ink)
    try chart_svg.append(&writer, &diagram.activations, ink)
    i = 0usize
    while i < diagram.messages.len {
        try chart_svg.append(&writer, &diagram.messages[i], ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, diagram.labels, ink, 9.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "auth") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_participant = [1]chart.SequenceMessage{ chart.SequenceMessage { from: 0usize, to: 3usize, kind: .Call, text: "bad" } }
    let bad_self_return = [1]chart.SequenceMessage{ chart.SequenceMessage { from: 1usize, to: 1usize, kind: .Return, text: "bad" } }
    let bad_activation = [1]chart.SequenceActivation{ chart.SequenceActivation { participant: 3usize, first: 0usize, last: 1usize } }
    let bad_range = [1]chart.SequenceActivation{ chart.SequenceActivation { participant: 1usize, first: 4usize, last: 2usize } }
    let (_, empty_error) = chart.sequence_diagram(participants[..0usize], messages[..], activations[..0usize], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, message_error) = chart.sequence_diagram(participants[..], messages[..0usize], activations[..0usize], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, participant_error) = chart.sequence_diagram(participants[..], bad_participant[..], activations[..0usize], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, self_error) = chart.sequence_diagram(participants[..], bad_self_return[..], activations[..0usize], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, activation_error) = chart.sequence_diagram(participants[..], messages[..], bad_activation[..], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, range_error) = chart.sequence_diagram(participants[..], messages[..], bad_range[..], bounds, headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, bounds_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], geometry.rect(0.0, 0.0, -1.0, 171.0), headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, width_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], geometry.rect(0.0, 0.0, 100.0, 171.0), headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, height_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], geometry.rect(0.0, 0.0, 328.0, 120.0), headers[..], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, header_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], bounds, headers[..2usize], lifelines[..], active[..], strokes[..], layers[..], labels[..])
    let (_, line_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], bounds, headers[..], lifelines[..29usize], active[..], strokes[..], layers[..], labels[..])
    let (_, stroke_error) = chart.sequence_diagram(participants[..], messages[..], activations[..], bounds, headers[..], lifelines[..], active[..], strokes[..47usize], layers[..], labels[..])
    if empty_error != chart.Empty || message_error != chart.Empty || participant_error != chart.Invalid || self_error != chart.Invalid || activation_error != chart.Invalid || range_error != chart.Invalid || bounds_error != chart.Invalid || width_error != chart.TooLarge || height_error != chart.TooLarge || header_error != chart.TooLarge || line_error != chart.TooLarge || stroke_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart sequence diagram ok\n")
    ret ok
}
