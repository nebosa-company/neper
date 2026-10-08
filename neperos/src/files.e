// Files (D2219): the app behind the Files icon, after Android's Files -- a storage summary on the top
// folder, folders and files as rows (a coloured tile with the type, the name, the size and date, or the
// number of items), a path under the title, a sort chip (Name, Date, Size), a back arrow up one folder,
// a sheet per item (type, size, modified, location; Open, Rename, Delete), and New folder and Rename on
// an on-screen keyboard. Dark ground, cream cards and amber, like the other apps (appkit.e, taps from
// the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app. The list
// scrolls with two arrow buttons.
// ponytail: the tree is SAMPLE data -- forty-odd made-up folders and files with sizes and dates, in this
// process, so every change is gone when the app closes; Open only says which app would open the file.
// Real storage through the filesystem server (fs_server.e), file operations between apps and the
// storage figures are queued as C125.
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use lunar

const NONE: usize = 99usize
const MAX_NODES: usize = 48usize
const MAX_HITS: usize = 96usize
const BROWSE_SCREEN: usize = 0usize
const ENTRY_SCREEN: usize = 1usize
const NEW_FOLDER: usize = 0usize
const RENAME: usize = 1usize
const FOLDER_KIND: usize = 12usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn say_text(value: str) {
    var buffer: [40]u8 = zero
    var n = 0usize
    while n < value.len && n < 40usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn number(a: *mem.Arena, value: usize) -> str {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, 20usize - at)
    if buffer_error != ok { ret "0" }
    var i = 0usize
    while at + i < 20usize {
        buffer[i] = digits[at + i]
        i += 1usize
    }
    ret buffer[0usize..20usize - at]
}

fn join(a: *mem.Arena, first: str, second: str, third: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + third.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < third.len {
        buffer[n] = third[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

fn text_of(a: *mem.Arena, bytes: []const u8, length: usize) -> str {
    let (copy, copy_error) = mem.alloc[u8](a, length + 1usize)
    if copy_error != ok { ret "" }
    var i = 0usize
    while i < length {
        copy[i] = bytes[i]
        i += 1usize
    }
    ret copy[0usize..length]
}

fn month_short(month: usize) -> str {
    if month == 0usize { ret "Jan" }
    if month == 1usize { ret "Feb" }
    if month == 2usize { ret "Mar" }
    if month == 3usize { ret "Apr" }
    if month == 4usize { ret "May" }
    if month == 5usize { ret "Jun" }
    if month == 6usize { ret "Jul" }
    if month == 7usize { ret "Aug" }
    if month == 8usize { ret "Sep" }
    if month == 9usize { ret "Oct" }
    if month == 10usize { ret "Nov" }
    ret "Dec"
}

// "84 KB", "2.1 MB" or "1.2 GB" from kilobytes.
fn size_text(a: *mem.Arena, kb: usize) -> str {
    if kb < 1024usize { ret join(a, number(a, kb), " KB", "") }
    if kb < 1048576usize { ret join(a, join(a, number(a, kb / 1024usize), ".", number(a, (kb % 1024usize) * 10usize / 1024usize)), " MB", "") }
    ret join(a, join(a, number(a, kb / 1048576usize), ".", number(a, (kb % 1048576usize) * 10usize / 1048576usize)), " GB", "")
}

// ----------------------------------------------------------------------------------------------
// State.

type Node = struct { name: [24]u8, name_len: usize, parent: usize, is_dir: bool, kb: usize, days_ago: usize, kind: usize, used: bool }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    nodes: [48]Node,
    cwd: usize,
    sort: usize,
    selected: usize,
    screen: usize,
    entry_mode: usize,
    entry: [24]u8,
    entry_len: usize,
    children: [48]usize,
    child_total: usize,
    scroll: f32,
    today: usize,
    note: usize,
    hits: [96]Hit,
    hit_total: usize,
}

// The file type from the name's extension.
fn kind_of(name: str) -> usize {
    var dot = name.len
    var i = 0usize
    while i < name.len {
        if name[i] == 46u8 { dot = i }
        i += 1usize
    }
    if dot >= name.len { ret 11usize }
    let ext = name[dot + 1usize..name.len]
    if same(ext, "txt") { ret 0usize }
    if same(ext, "md") { ret 1usize }
    if same(ext, "pdf") { ret 2usize }
    if same(ext, "doc") || same(ext, "docx") { ret 3usize }
    if same(ext, "xls") || same(ext, "xlsx") { ret 4usize }
    if same(ext, "ppt") || same(ext, "pptx") { ret 5usize }
    if same(ext, "jpg") || same(ext, "png") { ret 6usize }
    if same(ext, "mp3") { ret 7usize }
    if same(ext, "mp4") { ret 8usize }
    if same(ext, "zip") { ret 9usize }
    if same(ext, "ne") { ret 10usize }
    ret 11usize
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn kind_tag(kind: usize) -> str {
    if kind == 0usize { ret "TXT" }
    if kind == 1usize { ret "MD" }
    if kind == 2usize { ret "PDF" }
    if kind == 3usize { ret "DOC" }
    if kind == 4usize { ret "XLS" }
    if kind == 5usize { ret "PPT" }
    if kind == 6usize { ret "IMG" }
    if kind == 7usize { ret "MP3" }
    if kind == 8usize { ret "MP4" }
    if kind == 9usize { ret "ZIP" }
    if kind == 10usize { ret "NE" }
    if kind == 11usize { ret "FILE" }
    ret ""
}

fn kind_name(kind: usize) -> str {
    if kind == 0usize { ret "Text file" }
    if kind == 1usize { ret "Markdown" }
    if kind == 2usize { ret "PDF document" }
    if kind == 3usize { ret "Word document" }
    if kind == 4usize { ret "Spreadsheet" }
    if kind == 5usize { ret "Presentation" }
    if kind == 6usize { ret "Image" }
    if kind == 7usize { ret "Audio" }
    if kind == 8usize { ret "Video" }
    if kind == 9usize { ret "Archive" }
    if kind == 10usize { ret "Neper source" }
    if kind == 11usize { ret "File" }
    ret "Folder"
}

// Which app would open a type, said when Open is tapped.
fn opener_text(kind: usize) -> str {
    if kind >= 0usize && kind <= 5usize || kind == 10usize { ret "Opens in Document (not built yet)" }
    if kind == 6usize { ret "Opens in Photos" }
    if kind == 7usize || kind == 8usize { ret "No media player yet" }
    ret "No app for this type yet"
}

fn add_node(s: *State, name: str, parent: usize, is_dir: bool, kb: usize, days_ago: usize) -> usize {
    var i = 0usize
    while i < MAX_NODES {
        if !s.nodes[i].used {
            var n: Node = zero
            var k = 0usize
            while k < name.len && k < 24usize {
                n.name[k] = name[k]
                k += 1usize
            }
            n.name_len = k
            n.parent = parent
            n.is_dir = is_dir
            n.kb = kb
            n.days_ago = days_ago
            n.kind = FOLDER_KIND
            if !is_dir { n.kind = kind_of(name) }
            n.used = true
            s.nodes[i] = n
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn name_of(a: *mem.Arena, s: *State, index: usize) -> str {
    ret text_of(a, s.nodes[index].name[0usize..], s.nodes[index].name_len)
}

fn count_in(s: *State, folder: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_NODES {
        if s.nodes[i].used && s.nodes[i].parent == folder { n += 1usize }
        i += 1usize
    }
    ret n
}

// The bytes of a name in lower case, for sorting.
fn lower(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

// Does node `x` come before node `y` in the list: folders first, then by the sort chosen?
fn comes_before(s: *State, x: usize, y: usize) -> bool {
    let nx = s.nodes[x]
    let ny = s.nodes[y]
    if nx.is_dir != ny.is_dir { ret nx.is_dir }
    if s.sort == 1usize && nx.days_ago != ny.days_ago { ret nx.days_ago < ny.days_ago }
    if s.sort == 2usize && nx.kb != ny.kb { ret nx.kb > ny.kb }
    var i = 0usize
    while i < nx.name_len && i < ny.name_len {
        let cx = lower(nx.name[i])
        let cy = lower(ny.name[i])
        if cx != cy { ret cx < cy }
        i += 1usize
    }
    ret nx.name_len < ny.name_len
}

// The children of the folder shown, sorted.
fn build_children(s: *State) {
    s.child_total = 0usize
    var i = 0usize
    while i < MAX_NODES {
        if s.nodes[i].used && s.nodes[i].parent == s.cwd && i != s.cwd {
            // An insertion sort into the list.
            var at = s.child_total
            s.child_total += 1usize
            while at > 0usize && comes_before(s, i, s.children[at - 1usize]) {
                s.children[at] = s.children[at - 1usize]
                at -= 1usize
            }
            s.children[at] = i
        }
        i += 1usize
    }
}

// "Internal storage / Documents / Taxes".
fn path_text(a: *mem.Arena, s: *State, index: usize) -> str {
    if index == 0usize { ret name_of(a, s, 0usize) }
    ret join(a, path_text(a, s, s.nodes[index].parent), " / ", name_of(a, s, index))
}

fn date_text(a: *mem.Arena, s: *State, days_ago: usize) -> str {
    if days_ago == 0usize { ret "Today" }
    if days_ago == 1usize { ret "Yesterday" }
    let (month, date) = lunar.month_day((s.today - days_ago) * 86400usize)
    ret join(a, month_short(month), " ", number(a, date))
}

// Delete a node and everything below it.
fn remove_node(s: *State, index: usize) {
    s.nodes[index].used = false
    var pass = 0usize
    while pass < 5usize {
        var i = 0usize
        while i < MAX_NODES {
            if s.nodes[i].used && s.nodes[i].parent != NONE && !s.nodes[s.nodes[i].parent].used { s.nodes[i].used = false }
            i += 1usize
        }
        pass += 1usize
    }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream() -> paint.Color {
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn muted() -> paint.Color {
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

fn light() -> paint.Color {
    ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 }
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn amber_dark() -> paint.Color {
    ret paint.Color { red: 0.78, green: 0.52, blue: 0.12, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

// The tile colour of a type.
fn kind_color(kind: usize) -> paint.Color {
    if kind == 12usize { ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
    if kind == 2usize { ret paint.Color { red: 0.85, green: 0.45, blue: 0.40, alpha: 1.0 } }
    if kind == 3usize || kind == 1usize { ret paint.Color { red: 0.50, green: 0.64, blue: 0.88, alpha: 1.0 } }
    if kind == 4usize { ret paint.Color { red: 0.50, green: 0.78, blue: 0.55, alpha: 1.0 } }
    if kind == 5usize { ret paint.Color { red: 0.90, green: 0.62, blue: 0.40, alpha: 1.0 } }
    if kind == 6usize { ret paint.Color { red: 0.60, green: 0.80, blue: 0.70, alpha: 1.0 } }
    if kind == 7usize || kind == 8usize { ret paint.Color { red: 0.72, green: 0.58, blue: 0.85, alpha: 1.0 } }
    if kind == 9usize { ret paint.Color { red: 0.75, green: 0.62, blue: 0.48, alpha: 1.0 } }
    if kind == 10usize { ret paint.Color { red: 0.45, green: 0.75, blue: 0.80, alpha: 1.0 } }
    ret paint.Color { red: 0.70, green: 0.70, blue: 0.72, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn hit(s: *State, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if s.hit_total < MAX_HITS {
        s.hits[s.hit_total] = Hit { id: id, x: x, y: y, w: w, h: h }
        s.hit_total += 1usize
    }
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, right - text.measure(a, font, size, line), y, c)
}

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn chevron_icon(up: bool) -> str {
    if up { ret "<svg viewBox='0 0 24 24'><path d='M6 15l6-6 6 6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M6 9l6 6 6-6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn folder_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z' fill='currentColor'/></svg>"
}

fn sort_name(sort: usize) -> str {
    if sort == 0usize { ret "Name" }
    if sort == 1usize { ret "Date" }
    ret "Size"
}

// The storage summary on the top folder: the used space of the sample as a bar by category.
fn draw_storage(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try card(a, builder, 16.0, 92.0, 380.0, 104.0, 20.0, cream())
    try put(a, builder, faces.jost, 17.0, "Internal storage", 32.0, 104.0, ink())
    try put_right(a, builder, faces.grotesk, 13.0, "42.7 GB used of 128 GB", 380.0, 108.0, muted())
    // The bar: images, video, audio, documents, other.
    try card(a, builder, 32.0, 138.0, 348.0, 12.0, 6.0, soft())
    try card(a, builder, 32.0, 138.0, 112.0, 12.0, 6.0, paint.Color { red: 0.60, green: 0.80, blue: 0.70, alpha: 1.0 })
    try card(a, builder, 144.0, 138.0, 90.0, 12.0, 0.0, paint.Color { red: 0.72, green: 0.58, blue: 0.85, alpha: 1.0 })
    try card(a, builder, 234.0, 138.0, 34.0, 12.0, 0.0, paint.Color { red: 0.50, green: 0.64, blue: 0.88, alpha: 1.0 })
    try card(a, builder, 268.0, 138.0, 28.0, 12.0, 0.0, amber())
    try put(a, builder, faces.grotesk, 11.0, "Images", 32.0, 160.0, muted())
    try put(a, builder, faces.grotesk, 11.0, "Video and audio", 112.0, 160.0, muted())
    try put(a, builder, faces.grotesk, 11.0, "Documents", 232.0, 160.0, muted())
    try put(a, builder, faces.grotesk, 11.0, "Other", 322.0, 160.0, muted())
    ret ok
}

fn draw_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, index: usize, y: f32) -> err {
    let node = s.nodes[index]
    try card(a, builder, 16.0, y + 4.0, 380.0, 56.0, 16.0, cream())
    try card(a, builder, 26.0, y + 12.0, 40.0, 40.0, 12.0, kind_color(node.kind))
    if node.is_dir {
        try svg.draw(a, builder, folder_icon(), geometry.rect(34.0, y + 20.0, 24.0, 24.0), ink())
    } else {
        try centred(a, builder, faces.grotesk, 11.0, kind_tag(node.kind), 46.0, y + 24.0, ink())
    }
    try clipped(a, builder, faces.jost, 17.0, name_of(a, s, index), 78.0, y + 10.0, 250.0, ink())
    var detail = join(a, size_text(a, node.kb), "  ", date_text(a, s, node.days_ago))
    if node.is_dir {
        var count = " items"
        if count_in(s, index) == 1usize { count = " item" }
        detail = join(a, join(a, number(a, count_in(s, index)), count, "  "), date_text(a, s, node.days_ago), "")
    }
    try put(a, builder, faces.grotesk, 12.0, detail, 78.0, y + 36.0, muted())
    try put_right(a, builder, faces.jost_bold, 20.0, "...", 380.0, y + 18.0, muted())
    hit(s, 300usize + index, 330.0, y + 4.0, 66.0, 56.0)
    hit(s, 200usize + index, 16.0, y + 4.0, 314.0, 56.0)
    ret ok
}

fn draw_browse(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    build_children(s)
    var list_y: f32 = 96.0
    if s.cwd == 0usize {
        try put(a, builder, faces.jost_bold, 30.0, "Files", 20.0, 22.0, light())
        try draw_storage(a, builder, s, faces)
        list_y = 214.0
    } else {
        try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), light())
        hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
        try clipped(a, builder, faces.jost_bold, 26.0, name_of(a, s, s.cwd), 62.0, 14.0, 220.0, light())
        try clipped(a, builder, faces.grotesk, 12.0, path_text(a, s, s.cwd), 62.0, 54.0, 290.0, light_muted())
    }
    try pill(a, builder, s, faces, 700usize, 312.0, 20.0, 84.0, 34.0, sort_name(s.sort), soft(), 14.0)
    // The rows, shifted by the scroll; only whole rows are drawn.
    var pos = 0usize
    while pos < s.child_total {
        let y: f32 = list_y - s.scroll + f32(pos) * 64.0
        if y >= list_y - 1.0 && y + 64.0 <= 826.0 { try draw_row(a, builder, s, faces, s.children[pos], y) }
        pos += 1usize
    }
    if s.child_total == 0usize { try centred(a, builder, faces.jost, 19.0, "This folder is empty", 206.0, 300.0, light_muted()) }
    let content = f32(s.child_total) * 64.0
    let visible = 826.0 - list_y
    if content > visible {
        if s.scroll > 0.0 {
            try card(a, builder, 360.0, list_y + 6.0, 40.0, 40.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.65 })
            try svg.draw(a, builder, chevron_icon(true), geometry.rect(368.0, list_y + 14.0, 24.0, 24.0), light())
            hit(s, 800usize, 352.0, list_y, 56.0, 56.0)
        }
        if s.scroll + visible < content {
            try card(a, builder, 360.0, 770.0, 40.0, 40.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.65 })
            try svg.draw(a, builder, chevron_icon(false), geometry.rect(368.0, 778.0, 24.0, 24.0), light())
            hit(s, 801usize, 352.0, 764.0, 56.0, 56.0)
        }
    }
    // New folder.
    try card(a, builder, 252.0, 836.0, 144.0, 52.0, 26.0, amber())
    try card(a, builder, 274.0 - 8.0, 862.0 - 1.5, 16.0, 3.0, 1.5, ink())
    try card(a, builder, 274.0 - 1.5, 862.0 - 8.0, 3.0, 16.0, 1.5, ink())
    try put(a, builder, faces.jost, 16.0, "New folder", 292.0, 852.0, ink())
    hit(s, 150usize, 252.0, 836.0, 144.0, 52.0)
    if s.selected != NONE { try draw_sheet(a, builder, s, faces) }
    ret ok
}

// The sheet of the item selected: its details and what can be done.
fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let node = s.nodes[s.selected]
    try card(a, builder, 0.0, 84.0, 412.0, 812.0, 0.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.55 })
    hit(s, 614usize, 0.0, 84.0, 412.0, 352.0)
    try card(a, builder, 0.0, 436.0, 412.0, 460.0, 24.0, cream())
    hit(s, 615usize, 0.0, 436.0, 412.0, 460.0)
    try card(a, builder, 26.0, 456.0, 40.0, 40.0, 12.0, kind_color(node.kind))
    if node.is_dir {
        try svg.draw(a, builder, folder_icon(), geometry.rect(34.0, 464.0, 24.0, 24.0), ink())
    } else {
        try centred(a, builder, faces.grotesk, 11.0, kind_tag(node.kind), 46.0, 468.0, ink())
    }
    try clipped(a, builder, faces.jost_bold, 20.0, name_of(a, s, s.selected), 80.0, 466.0, 310.0, ink())
    var row = 0usize
    while row < 4usize {
        var label = "Type"
        var value = kind_name(node.kind)
        if row == 1usize {
            label = "Size"
            value = size_text(a, node.kb)
            if node.is_dir {
                value = join(a, number(a, count_in(s, s.selected)), " items", "")
            }
        }
        if row == 2usize {
            label = "Modified"
            value = date_text(a, s, node.days_ago)
        }
        if row == 3usize {
            label = "Location"
            value = name_of(a, s, node.parent)
        }
        let y: f32 = 516.0 + f32(row) * 32.0
        try put(a, builder, faces.grotesk, 13.0, label, 32.0, y + 6.0, muted())
        try put_right(a, builder, faces.jost, 17.0, value, 380.0, y + 3.0, ink())
        row += 1usize
    }
    if s.note == 1usize { try centred(a, builder, faces.grotesk, 13.0, opener_text(node.kind), 206.0, 654.0, amber_dark()) }
    try pill(a, builder, s, faces, 610usize, 16.0, 690.0, 118.0, 48.0, "Open", amber(), 16.0)
    try pill(a, builder, s, faces, 611usize, 147.0, 690.0, 118.0, 48.0, "Rename", soft(), 16.0)
    try pill(a, builder, s, faces, 612usize, 278.0, 690.0, 118.0, 48.0, "Delete", soft(), 16.0)
    try pill(a, builder, s, faces, 613usize, 16.0, 754.0, 380.0, 48.0, "Close", soft(), 16.0)
    ret ok
}

// ---- the keyboard (the same as Wallet's).

fn number_label(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    if n == 7usize { ret "7" }
    if n == 8usize { ret "8" }
    ret "9"
}

fn letter_row(row: usize) -> str {
    if row == 0usize { ret "qwertyuiop" }
    if row == 1usize { ret "asdfghjkl" }
    ret "zxcvbnm"
}

fn key_cap(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 2.0, w, 48.0, 10.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.35 })
    try card(a, builder, x, y, w, 48.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 20.0, label, x + w / 2.0, y + 24.0 - 12.0, ink())
    hit(s, id, x, y, w, 48.0)
    ret ok
}

fn draw_keyboard(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var d = 0usize
    while d < 10usize {
        try key_cap(a, builder, s, faces, 1100usize + d, 18.0 + f32(d) * 38.0, 500.0, 34.0, number_label((d + 1usize) % 10usize), soft())
        d += 1usize
    }
    var row = 0usize
    while row < 3usize {
        let letters = letter_row(row)
        var x0: f32 = 18.0
        if row == 1usize { x0 = 37.0 }
        if row == 2usize { x0 = 18.0 + 52.0 }
        var k = 0usize
        while k < letters.len {
            let ch = usize(letters[k])
            let (one, one_error) = mem.alloc[u8](a, 1usize)
            if one_error != ok { ret one_error }
            one[0usize] = letters[k]
            try key_cap(a, builder, s, faces, 1000usize + ch - 97usize, x0 + f32(k) * 38.0, 558.0 + f32(row) * 58.0, 34.0, one[0usize..1usize], cream())
            k += 1usize
        }
        row += 1usize
    }
    try key_cap(a, builder, s, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, s, faces, 1203usize, 18.0, 732.0, 44.0, "-", soft())
    try key_cap(a, builder, s, faces, 1204usize, 68.0, 732.0, 44.0, "_", soft())
    try key_cap(a, builder, s, faces, 1200usize, 118.0, 732.0, 130.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 254.0, 732.0, 44.0, ".", soft())
    try key_cap(a, builder, s, faces, 1205usize, 304.0, 732.0, 90.0, "Enter", amber())
    ret ok
}

fn draw_entry(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "New folder"
    if s.entry_mode == RENAME { heading = "Rename" }
    try put(a, builder, faces.jost_bold, 30.0, heading, 24.0, 28.0, light())
    try put(a, builder, faces.grotesk, 12.0, join(a, "In ", path_text(a, s, s.cwd), ""), 24.0, 74.0, light_muted())
    let value = text_of(a, s.entry[0usize..], s.entry_len)
    try card(a, builder, 14.0, 104.0, 384.0, 54.0, 18.0, amber())
    try card(a, builder, 16.0, 106.0, 380.0, 50.0, 16.0, cream())
    try clipped(a, builder, faces.jost, 20.0, value, 32.0, 119.0, 340.0, ink())
    var caret_x: f32 = 32.0
    if value.len > 0usize { caret_x = 32.0 + text.measure(a, faces.jost, 20.0, value) + 2.0 }
    if caret_x > 372.0 { caret_x = 372.0 }
    try card(a, builder, caret_x, 117.0, 2.0, 26.0, 1.0, amber())
    try pill(a, builder, s, faces, 1300usize, 16.0, 180.0, 186.0, 48.0, "Save", amber(), 17.0)
    try pill(a, builder, s, faces, 1302usize, 210.0, 180.0, 186.0, 48.0, "Cancel", soft(), 17.0)
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.screen == BROWSE_SCREEN {
        try draw_browse(a, builder, s, faces)
    } else {
        try draw_entry(a, builder, s, faces)
    }
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn type_byte(s: *State, byte: u8) {
    if s.entry_len >= 24usize { ret }
    s.entry[s.entry_len] = byte
    s.entry_len += 1usize
}

fn open_entry(s: *State, mode: usize) {
    s.screen = ENTRY_SCREEN
    s.entry_mode = mode
    s.entry_len = 0usize
    if mode == RENAME {
        let node = s.nodes[s.selected]
        var i = 0usize
        while i < node.name_len {
            s.entry[i] = node.name[i]
            i += 1usize
        }
        s.entry_len = node.name_len
    }
}

// Is `name` free in the folder shown (a different node)?
fn name_free(s: *State, name: str, except: usize) -> bool {
    var i = 0usize
    while i < MAX_NODES {
        if s.nodes[i].used && s.nodes[i].parent == s.cwd && i != except {
            if same(text_of_static(s, i), name) { ret false }
        }
        i += 1usize
    }
    ret true
}

fn text_of_static(s: *State, index: usize) -> str {
    ret s.nodes[index].name[0usize..s.nodes[index].name_len]
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == ENTRY_SCREEN {
        if id >= 1000usize && id < 1026usize {
            type_byte(s, u8(97usize + id - 1000usize))
            ret true
        }
        if id >= 1100usize && id < 1110usize {
            type_byte(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
            ret true
        }
        if id == 1200usize {
            type_byte(s, 32u8)
            ret true
        }
        if id == 1201usize {
            if s.entry_len > 0usize { s.entry_len -= 1usize }
            ret true
        }
        if id == 1202usize {
            type_byte(s, 46u8)
            ret true
        }
        if id == 1203usize {
            type_byte(s, 45u8)
            ret true
        }
        if id == 1204usize {
            type_byte(s, 95u8)
            ret true
        }
        if id == 1300usize || id == 1205usize {
            // The first letter of a new folder is a capital.
            var typed = text_of(a, s.entry[0usize..], s.entry_len)
            if s.entry_mode == NEW_FOLDER && s.entry_len > 0usize && s.entry[0usize] >= 97u8 && s.entry[0usize] <= 122u8 {
                s.entry[0usize] = s.entry[0usize] - 32u8
                typed = text_of(a, s.entry[0usize..], s.entry_len)
            }
            let except = s.selected
            if s.entry_len > 0usize && name_free(s, typed, except) {
                if s.entry_mode == NEW_FOLDER {
                    let made = add_node(s, typed, s.cwd, true, 0usize, 0usize)
                    if made != NONE {
                        say("files created ")
                        say_text(typed)
                        say("\n")
                    }
                } else {
                    var k = 0usize
                    while k < s.entry_len {
                        s.nodes[except].name[k] = s.entry[k]
                        k += 1usize
                    }
                    s.nodes[except].name_len = s.entry_len
                    if !s.nodes[except].is_dir { s.nodes[except].kind = kind_of(typed) }
                    say("files renamed ")
                    say_text(typed)
                    say("\n")
                }
            }
            s.selected = NONE
            s.screen = BROWSE_SCREEN
            ret true
        }
        if id == 1302usize {
            s.selected = NONE
            s.screen = BROWSE_SCREEN
            ret true
        }
        ret false
    }
    // A sheet is open: its buttons, or a tap outside closes it.
    if s.selected != NONE {
        if id == 610usize {
            s.note = 1usize
            if s.nodes[s.selected].is_dir {
                s.cwd = s.selected
                s.selected = NONE
                s.scroll = 0.0
                s.note = 0usize
                ret true
            }
            say("files open ")
            say_text(text_of_static(s, s.selected))
            say("\n")
            ret true
        }
        if id == 611usize {
            open_entry(s, RENAME)
            ret true
        }
        if id == 612usize {
            say("files deleted ")
            say_text(text_of_static(s, s.selected))
            say("\n")
            remove_node(s, s.selected)
            s.selected = NONE
            s.note = 0usize
            ret true
        }
        if id == 613usize || id == 614usize {
            s.selected = NONE
            s.note = 0usize
            ret true
        }
        ret false
    }
    if id >= 200usize && id < 200usize + MAX_NODES {
        let index = id - 200usize
        if s.nodes[index].is_dir {
            s.cwd = index
            s.scroll = 0.0
            say("files folder ")
            say_text(text_of_static(s, index))
            say("\n")
        } else {
            s.selected = index
            s.note = 0usize
            say("files file ")
            say_text(text_of_static(s, index))
            say("\n")
        }
        ret true
    }
    if id >= 300usize && id < 300usize + MAX_NODES {
        s.selected = id - 300usize
        s.note = 0usize
        ret true
    }
    if id == 500usize {
        s.cwd = s.nodes[s.cwd].parent
        s.scroll = 0.0
        say("files up\n")
        ret true
    }
    if id == 700usize {
        s.sort = (s.sort + 1usize) % 3usize
        say("files sort ")
        say(sort_name(s.sort))
        say("\n")
        ret true
    }
    if id == 150usize {
        s.selected = NONE
        open_entry(s, NEW_FOLDER)
        ret true
    }
    if id == 800usize {
        s.scroll -= 256.0
        if s.scroll < 0.0 { s.scroll = 0.0 }
        ret true
    }
    if id == 801usize {
        s.scroll += 256.0
        ret true
    }
    ret false
}

fn hit_at(s: *State, x: f32, y: f32) -> usize {
    var i = s.hit_total
    while i > 0usize {
        i -= 1usize
        let h = s.hits[i]
        if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h { ret h.id }
    }
    ret NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "files")
    if kit_error != ok {
        say("files open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("files fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.selected = NONE
    let (wall, wall_error) = time.now()
    if wall_error == ok { s.today = usize(wall.nanos / 1000000000i64) / 86400usize }
    if s.today < 400usize { s.today = 400usize }
    // The sample tree.
    let root = add_node(&s, "Internal storage", NONE, true, 0usize, 0usize)
    let documents = add_node(&s, "Documents", root, true, 0usize, 2usize)
    let downloads = add_node(&s, "Downloads", root, true, 0usize, 0usize)
    let pictures = add_node(&s, "Pictures", root, true, 0usize, 1usize)
    let music = add_node(&s, "Music", root, true, 0usize, 12usize)
    let movies = add_node(&s, "Movies", root, true, 0usize, 30usize)
    let projects = add_node(&s, "Projects", root, true, 0usize, 3usize)
    let n1 = add_node(&s, "notes.txt", root, false, 4usize, 0usize)
    let taxes = add_node(&s, "Taxes", documents, true, 0usize, 40usize)
    let d1 = add_node(&s, "Resume.docx", documents, false, 84usize, 9usize)
    let d2 = add_node(&s, "Passport scan.pdf", documents, false, 2150usize, 21usize)
    let d3 = add_node(&s, "Lease.pdf", documents, false, 640usize, 60usize)
    let d4 = add_node(&s, "Budget.xlsx", documents, false, 212usize, 2usize)
    let t1 = add_node(&s, "Tax 2025.pdf", taxes, false, 1380usize, 40usize)
    let t2 = add_node(&s, "Receipts.zip", taxes, false, 18400usize, 41usize)
    let w1 = add_node(&s, "report-q3.pdf", downloads, false, 3120usize, 0usize)
    let w2 = add_node(&s, "slides.pptx", downloads, false, 8420usize, 1usize)
    let w3 = add_node(&s, "readme.md", downloads, false, 6usize, 4usize)
    let w4 = add_node(&s, "photo-001.jpg", downloads, false, 3880usize, 4usize)
    let w5 = add_node(&s, "setup.zip", downloads, false, 52300usize, 6usize)
    let w6 = add_node(&s, "invoice-882.pdf", downloads, false, 190usize, 7usize)
    let camera = add_node(&s, "Camera", pictures, true, 0usize, 0usize)
    let shots = add_node(&s, "Screenshots", pictures, true, 0usize, 2usize)
    let p1 = add_node(&s, "Family-dinner.jpg", pictures, false, 4210usize, 9usize)
    let c1 = add_node(&s, "IMG_3000.jpg", camera, false, 5100usize, 0usize)
    let c2 = add_node(&s, "IMG_3017.jpg", camera, false, 4800usize, 0usize)
    let c3 = add_node(&s, "IMG_3034.jpg", camera, false, 5300usize, 1usize)
    let m1 = add_node(&s, "Evening.mp3", music, false, 7400usize, 12usize)
    let m2 = add_node(&s, "Road trip.mp3", music, false, 9100usize, 12usize)
    let m3 = add_node(&s, "Podcast-12.mp3", music, false, 41200usize, 15usize)
    let v1 = add_node(&s, "Holiday.mp4", movies, false, 421000usize, 30usize)
    let r1 = add_node(&s, "hello.ne", projects, false, 2usize, 3usize)
    let r2 = add_node(&s, "calc.ne", projects, false, 41usize, 5usize)
    let r3 = add_node(&s, "README.md", projects, false, 3usize, 5usize)
    if !show(a, &kit, &s) {
        say("files present failed\n")
        ret ok
    }
    say("files shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("files home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    say("files present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
