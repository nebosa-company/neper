use e.fs
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str
use e.text.shape

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let words = [4]str{ "alpha", "beta", "gamma", "the" }
    let weights = [4]f32{ 9.0, 4.0, 1.0, 100.0 }
    let widths = [4]f32{ 4.0, 3.0, 3.0, 2.0 }
    let heights = [4]f32{ 1.0, 1.0, 1.0, 1.0 }
    let excluded = [1]str{ "the" }
    let bounds = geometry.rect(0.0, 0.0, 180.0, 100.0)
    var order: [4]usize = zero
    var storage: [4]chart.CloudWord = zero
    let (marks, cloud_error) = chart.word_cloud(words[..], weights[..], widths[..], heights[..], 0.8, excluded[..], bounds, 8.0, 24.0, 2.0, order[..], storage[..])
    if cloud_error != ok || marks.len != 3usize || !str.eq(marks[0usize].label.text, "alpha") || !near(marks[0usize].size, 24.0) || !str.eq(marks[1usize].label.text, "beta") || !near(marks[1usize].size, 16.0) || !str.eq(marks[2usize].label.text, "gamma") || !near(marks[2usize].size, 8.0) { ret chart.Invalid }
    var i = 0usize
    while i < marks.len {
        let box = marks[i].box
        if box.x < bounds.x || box.y < bounds.y || box.x + box.width > bounds.x + bounds.width || box.y + box.height > bounds.y + bounds.height { ret chart.Invalid }
        var j = 0usize
        while j < i {
            let prior = marks[j].box
            if box.x < prior.x + prior.width + 2.0 && box.x + box.width + 2.0 > prior.x && box.y < prior.y + prior.height + 2.0 && box.y + box.height + 2.0 > prior.y { ret chart.Invalid }
            j += 1usize
        }
        i += 1usize
    }
    let duplicates = [2]str{ "same", "same" }
    let pair_weights = [2]f32{ 2.0, 1.0 }
    let pair_widths = [2]f32{ 2.0, 2.0 }
    let pair_heights = [2]f32{ 1.0, 1.0 }
    let (_, duplicate_error) = chart.word_cloud(duplicates[..], pair_weights[..], pair_widths[..], pair_heights[..], 0.8, excluded[..0usize], bounds, 8.0, 24.0, 2.0, order[..], storage[..])
    if duplicate_error != chart.Invalid { ret chart.Invalid }
    let negative = [4]f32{ 9.0, -1.0, 1.0, 100.0 }
    let (_, negative_error) = chart.word_cloud(words[..], negative[..], widths[..], heights[..], 0.8, excluded[..], bounds, 8.0, 24.0, 2.0, order[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, empty_error) = chart.word_cloud(words[3usize..], weights[3usize..], widths[3usize..], heights[3usize..], 0.8, excluded[..], bounds, 8.0, 24.0, 2.0, order[..], storage[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (_, capacity_error) = chart.word_cloud(words[..], weights[..], widths[..], heights[..], 0.8, excluded[..], bounds, 8.0, 24.0, 2.0, order[..3usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, fitting_error) = chart.word_cloud(words[..], weights[..], widths[..], heights[..], 0.8, excluded[..], geometry.rect(0.0, 0.0, 40.0, 40.0), 8.0, 24.0, 2.0, order[..], storage[..])
    if fitting_error != chart.TooLarge { ret chart.Invalid }
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    i = 0usize
    while i < marks.len {
        let label = [1]chart.Label{ marks[i].label }
        try chart_scene.append_labels(a, &builder, label[..], font, marks[i].size, paint.Brush { Solid: ink })
        i += 1usize
    }
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 180.0, 100.0, "Word cloud", "Weighted tokens")
    i = 0usize
    while i < marks.len {
        let label = [1]chart.Label{ marks[i].label }
        try chart_svg.append_labels(&writer, label[..], ink, marks[i].size)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "alpha") || !str.contains(svg, "gamma") || str.contains(svg, ">the<") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart word cloud ok\n")
    ret ok
}
