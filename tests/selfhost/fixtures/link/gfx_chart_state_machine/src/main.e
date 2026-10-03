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
    let states = [4]chart.MachineState{
        chart.MachineState { center: chart.Coord { x: 65.0, y: 137.0 }, initial: true, final: false },
        chart.MachineState { center: chart.Coord { x: 155.0, y: 90.0 }, initial: false, final: false },
        chart.MachineState { center: chart.Coord { x: 265.0, y: 90.0 }, initial: false, final: true },
        chart.MachineState { center: chart.Coord { x: 155.0, y: 180.0 }, initial: false, final: true },
    }
    let events = [6]str{ "open", "ok", "fail", "close", "reset", "refresh" }
    let transitions = [6]chart.MachineTransition{
        chart.MachineTransition { from: 0usize, to: 1usize, event: 0usize },
        chart.MachineTransition { from: 1usize, to: 2usize, event: 1usize },
        chart.MachineTransition { from: 1usize, to: 3usize, event: 2usize },
        chart.MachineTransition { from: 2usize, to: 3usize, event: 3usize },
        chart.MachineTransition { from: 3usize, to: 0usize, event: 4usize },
        chart.MachineTransition { from: 2usize, to: 2usize, event: 5usize },
    }
    let (next, fired, step_error) = chart.state_machine_step(4usize, 0usize, 0usize, transitions[..])
    let (stayed, missing, missing_error) = chart.state_machine_step(4usize, 0usize, 5usize, transitions[..])
    let (looped, loop_fired, loop_error) = chart.state_machine_step(4usize, 2usize, 5usize, transitions[..])
    if step_error != ok || !fired || next != 1usize || missing_error != ok || missing || stayed != 0usize || loop_error != ok || !loop_fired || looped != 2usize { ret chart.Invalid }
    let duplicate = [2]chart.MachineTransition{
        chart.MachineTransition { from: 0usize, to: 1usize, event: 0usize },
        chart.MachineTransition { from: 0usize, to: 2usize, event: 0usize },
    }
    let bad_event = [1]chart.MachineTransition{ chart.MachineTransition { from: 0usize, to: 1usize, event: 6usize } }
    let bad_state = [1]chart.MachineTransition{ chart.MachineTransition { from: 0usize, to: 4usize, event: 0usize } }
    let (_, _, duplicate_step_error) = chart.state_machine_step(4usize, 0usize, 0usize, duplicate[..])
    let (_, _, index_step_error) = chart.state_machine_step(4usize, 0usize, 0usize, bad_state[..])
    let (_, _, empty_step_error) = chart.state_machine_step(0usize, 0usize, 0usize, transitions[..0usize])
    if duplicate_step_error != chart.Invalid || index_step_error != chart.Invalid || empty_step_error != chart.Empty { ret chart.Invalid }
    let bounds = geometry.rect(18.0, 45.0, 324.0, 176.0)
    var outlines: [96]chart.Coord = zero
    var shapes: [4]chart.Layout = zero
    var arrows: [30]chart.Segment = zero
    var rings: [48]chart.Segment = zero
    var start: [3]chart.Segment = zero
    var labels: [6]chart.Label = zero
    let (machine, result) = chart.state_machine(states[..], transitions[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    if result != ok || machine.states.len != 4usize || machine.transitions.segments.len != 20usize || machine.initial_marker.segments.len != 3usize || machine.final_rings.segments.len != 48usize || machine.event_labels.len != 6usize { ret chart.Invalid }
    if shapes[0usize].kind != .Area || shapes[0usize].coords.len != 24usize || !str.contains(labels[5usize].text, "refresh") || start[0usize].from.x >= start[0usize].to.x || rings[0usize].from.x == rings[0usize].to.x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 96usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < machine.states.len {
        try chart_scene.append(a, &builder, &machine.states[i], paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &machine.transitions, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &machine.initial_marker, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &machine.final_rings, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 75usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 250.0, "State machine", "Event transitions")
    i = 0usize
    while i < machine.states.len {
        try chart_svg.append(&writer, &machine.states[i], ink)
        i += 1usize
    }
    try chart_svg.append(&writer, &machine.transitions, ink)
    try chart_svg.append(&writer, &machine.initial_marker, ink)
    try chart_svg.append(&writer, &machine.final_rings, ink)
    try chart_svg.append_labels(&writer, machine.event_labels, ink, 8.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "refresh") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let extra_initial = [2]chart.MachineState{ states[0usize], chart.MachineState { center: chart.Coord { x: 155.0, y: 90.0 }, initial: true, final: false } }
    let missing_initial = [1]chart.MachineState{ chart.MachineState { center: chart.Coord { x: 65.0, y: 137.0 }, initial: false, final: false } }
    let overlapping = [2]chart.MachineState{ states[0usize], states[0usize] }
    let near_left = [1]chart.MachineState{ chart.MachineState { center: chart.Coord { x: 40.0, y: 137.0 }, initial: true, final: false } }
    let near_top = [1]chart.MachineState{ chart.MachineState { center: chart.Coord { x: 120.0, y: 68.0 }, initial: true, final: false } }
    let self_loop = [1]chart.MachineTransition{ chart.MachineTransition { from: 0usize, to: 0usize, event: 0usize } }
    let (_, empty_error) = chart.state_machine(states[..0usize], transitions[..0usize], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, initial_error) = chart.state_machine(extra_initial[..], transitions[..0usize], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, missing_error2) = chart.state_machine(missing_initial[..], transitions[..0usize], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, overlap_error) = chart.state_machine(overlapping[..], transitions[..0usize], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, event_error) = chart.state_machine(states[..], bad_event[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, duplicate_error) = chart.state_machine(states[..], duplicate[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, bad_index_error) = chart.state_machine(states[..], bad_state[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, left_error) = chart.state_machine(near_left[..], transitions[..0usize], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, top_error) = chart.state_machine(near_top[..], self_loop[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, radius_error) = chart.state_machine(states[..], transitions[..], events[..], bounds, 5.0, outlines[..], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, outline_error) = chart.state_machine(states[..], transitions[..], events[..], bounds, 21.0, outlines[..95usize], shapes[..], arrows[..], rings[..], start[..], labels[..])
    let (_, arrow_error) = chart.state_machine(states[..], transitions[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..29usize], rings[..], start[..], labels[..])
    let (_, ring_error) = chart.state_machine(states[..], transitions[..], events[..], bounds, 21.0, outlines[..], shapes[..], arrows[..], rings[..47usize], start[..], labels[..])
    if empty_error != chart.Empty || initial_error != chart.Invalid || missing_error2 != chart.Invalid || overlap_error != chart.Invalid || event_error != chart.Invalid || duplicate_error != chart.Invalid || bad_index_error != chart.Invalid || left_error != chart.TooLarge || top_error != chart.TooLarge || radius_error != chart.Invalid || outline_error != chart.TooLarge || arrow_error != chart.TooLarge || ring_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart state machine ok\n")
    ret ok
}
