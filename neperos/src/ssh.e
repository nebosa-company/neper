// SSH (D2215): the app behind the SSH icon, after Termius -- a list of hosts (a round terminal glyph, the
// alias, user@address, a dot for the ones used before), a form to add, edit or delete a host (alias,
// address, user, port, password or key) with an on-screen keyboard, and a terminal screen with a prompt,
// the output above it, a command history on the arrow keys, Ctrl-C and Clear, and the keyboard with a
// row of extra keys. Dark ground, cream rows and amber, like the other apps (appkit.e, taps from the
// compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: there is NO network yet (queue item C117), so Connect opens a LOCAL DEMO session, said so on
// screen: a small shell of sample commands (help, ls, pwd, whoami, hostname, date, uname, uptime, echo,
// clear, exit) that never leaves the process. The real client (key exchange, authentication, channels,
// keys kept in Secure, SFTP, port forwarding) is queued as C120. The hosts live in the process too.
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
const MAX_HOSTS: usize = 8usize
const MAX_LINES: usize = 64usize
const VISIBLE: usize = 18usize
const MAX_HITS: usize = 96usize
const HOSTS_SCREEN: usize = 0usize
const FORM_SCREEN: usize = 1usize
const TERMINAL_SCREEN: usize = 2usize

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

fn weekday_short(day: usize) -> str {
    if day == 0usize { ret "Mon" }
    if day == 1usize { ret "Tue" }
    if day == 2usize { ret "Wed" }
    if day == 3usize { ret "Thu" }
    if day == 4usize { ret "Fri" }
    if day == 5usize { ret "Sat" }
    ret "Sun"
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

// "Thu Oct 8 22:23 UTC" from the wall clock.
fn date_text(a: *mem.Arena) -> str {
    let (wall, wall_error) = time.now()
    if wall_error != ok { ret "date: no clock" }
    let seconds = usize(wall.nanos / 1000000000i64)
    let (month, date) = lunar.month_day(seconds)
    let weekday = (seconds / 86400usize + 3usize) % 7usize
    let minutes = (seconds % 86400usize) / 60usize
    var tens = ""
    if minutes % 60usize < 10usize { tens = "0" }
    ret join(a, join(a, weekday_short(weekday), " ", month_short(month)), " ", join(a, join(a, number(a, date), " ", number(a, minutes / 60usize)), ":", join(a, tens, number(a, minutes % 60usize), " UTC")))
}

// ----------------------------------------------------------------------------------------------
// State.

type Host = struct { alias: [16]u8, alias_len: usize, addr: [24]u8, addr_len: usize, user: [12]u8, user_len: usize, port: usize, key_auth: bool, seen: bool, used: bool }

type Line = struct { body: [48]u8, length: usize, kind: usize }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    hosts: [8]Host,
    screen: usize,
    // The host being connected to or edited, and the draft of the form.
    current: usize,
    editing: usize,
    draft: Host,
    focus: usize,
    // The terminal: the lines above the prompt, the command being typed and the last few commands.
    lines: [64]Line,
    line_total: usize,
    cmd: [40]u8,
    cmd_len: usize,
    history: [160]u8,
    history_len: [4]usize,
    history_total: usize,
    history_at: usize,
    hits: [96]Hit,
    hit_total: usize,
}

fn make_host(alias: str, addr: str, user: str, port: usize, key_auth: bool, seen: bool) -> Host {
    var h: Host = zero
    var i = 0usize
    while i < alias.len && i < 16usize {
        h.alias[i] = alias[i]
        i += 1usize
    }
    h.alias_len = i
    i = 0usize
    while i < addr.len && i < 24usize {
        h.addr[i] = addr[i]
        i += 1usize
    }
    h.addr_len = i
    i = 0usize
    while i < user.len && i < 12usize {
        h.user[i] = user[i]
        i += 1usize
    }
    h.user_len = i
    h.port = port
    h.key_auth = key_auth
    h.seen = seen
    h.used = true
    ret h
}

fn add_host(s: *State, host: Host) -> bool {
    var i = 0usize
    while i < MAX_HOSTS {
        if !s.hosts[i].used {
            s.hosts[i] = host
            ret true
        }
        i += 1usize
    }
    ret false
}

fn count_hosts(s: *State) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        if s.hosts[i].used { n += 1usize }
        i += 1usize
    }
    ret n
}

fn alias_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.alias[0usize..], h.alias_len)
}

fn user_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.user[0usize..], h.user_len)
}

fn addr_of(a: *mem.Arena, h: Host) -> str {
    ret text_of(a, h.addr[0usize..], h.addr_len)
}

// ----------------------------------------------------------------------------------------------
// The demo shell.

fn push_line(s: *State, body: str, kind: usize) {
    if s.line_total == MAX_LINES {
        var k = 1usize
        while k < MAX_LINES {
            s.lines[k - 1usize] = s.lines[k]
            k += 1usize
        }
        s.line_total -= 1usize
    }
    var line: Line = zero
    var i = 0usize
    while i < body.len && i < 48usize {
        line.body[i] = body[i]
        i += 1usize
    }
    line.length = i
    line.kind = kind
    s.lines[s.line_total] = line
    s.line_total += 1usize
}

fn prompt_text(a: *mem.Arena, s: *State) -> str {
    let h = s.hosts[s.current]
    ret join(a, join(a, user_of(a, h), "@", alias_of(a, h)), ":~$ ", "")
}

fn command_is(s: *State, word: str) -> bool {
    if s.cmd_len != word.len { ret false }
    var i = 0usize
    while i < word.len {
        if s.cmd[i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

fn command_starts(s: *State, word: str) -> bool {
    if s.cmd_len < word.len { ret false }
    var i = 0usize
    while i < word.len {
        if s.cmd[i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

fn remember(s: *State) {
    if s.cmd_len == 0usize { ret }
    // The newest command goes in slot 0 of four; the others move down.
    var slot = 3usize
    while slot > 0usize {
        var i = 0usize
        while i < 40usize {
            s.history[slot * 40usize + i] = s.history[(slot - 1usize) * 40usize + i]
            i += 1usize
        }
        s.history_len[slot] = s.history_len[slot - 1usize]
        slot -= 1usize
    }
    var j = 0usize
    while j < s.cmd_len {
        s.history[j] = s.cmd[j]
        j += 1usize
    }
    s.history_len[0usize] = s.cmd_len
    if s.history_total < 4usize { s.history_total += 1usize }
}

// Run the command typed: echo it with its prompt, print the output, start a new line.
fn run_command(a: *mem.Arena, s: *State) {
    let typed = text_of(a, s.cmd[0usize..], s.cmd_len)
    push_line(s, join(a, prompt_text(a, s), typed, ""), 1usize)
    remember(s)
    s.history_at = 0usize
    if s.cmd_len > 0usize {
        say("ssh command ")
        say_text(typed)
        say("\n")
    }
    let h = s.hosts[s.current]
    if s.cmd_len == 0usize {
    } else if command_is(s, "help") {
        push_line(s, "help ls pwd whoami hostname date uname", 0usize)
        push_line(s, "uptime echo clear exit", 0usize)
    } else if command_is(s, "ls") {
        push_line(s, "bin  docs  logs  notes.txt  projects", 0usize)
    } else if command_is(s, "pwd") {
        push_line(s, join(a, "/home/", user_of(a, h), ""), 0usize)
    } else if command_is(s, "whoami") {
        push_line(s, user_of(a, h), 0usize)
    } else if command_is(s, "hostname") {
        push_line(s, alias_of(a, h), 0usize)
    } else if command_is(s, "date") {
        push_line(s, date_text(a), 0usize)
    } else if command_is(s, "uname") {
        push_line(s, join(a, "Linux ", alias_of(a, h), " 6.8.0 aarch64"), 0usize)
    } else if command_is(s, "uptime") {
        push_line(s, "up 12 days, 3:41, load 0.12 0.09 0.05", 0usize)
    } else if command_starts(s, "echo ") {
        push_line(s, text_of(a, s.cmd[5usize..], s.cmd_len - 5usize), 0usize)
    } else if command_is(s, "clear") {
        s.line_total = 0usize
    } else if command_is(s, "exit") {
        s.screen = HOSTS_SCREEN
        say("ssh closed\n")
    } else {
        push_line(s, join(a, "sh: ", typed, ": command not found"), 0usize)
    }
    s.cmd_len = 0usize
}

fn connect(a: *mem.Arena, s: *State, index: usize) {
    s.current = index
    s.hosts[index].seen = true
    s.screen = TERMINAL_SCREEN
    s.line_total = 0usize
    s.cmd_len = 0usize
    s.history_at = 0usize
    let h = s.hosts[index]
    push_line(s, "Local demo session: no network yet.", 2usize)
    push_line(s, join(a, join(a, "Connected to ", alias_of(a, h), " ("), join(a, user_of(a, h), "@", join(a, addr_of(a, h), ":", join(a, number(a, h.port), ")", ""))), ""), 2usize)
    push_line(s, "Type help for commands.", 2usize)
    say("ssh connected ")
    say_text(alias_of(a, h))
    say("\n")
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

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn tint_of(index: usize) -> paint.Color {
    let n = index % 6usize
    if n == 0usize { ret paint.Color { red: 0.85, green: 0.60, blue: 0.45, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.55, green: 0.72, blue: 0.62, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.60, green: 0.66, blue: 0.85, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.82, green: 0.62, blue: 0.75, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.88, green: 0.76, blue: 0.45, alpha: 1.0 } }
    ret paint.Color { red: 0.62, green: 0.78, blue: 0.80, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn disc(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.ellipse_path(a, cx, cy, radius, radius)
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

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn prompt_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M4 7l6 5-6 5' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/><path d='M12 18h8' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round'/></svg>"
}

// ---- the keyboard: digits, three rows of letters, a row with - / space . and Enter.

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
    try key_cap(a, builder, s, faces, 1204usize, 68.0, 732.0, 44.0, "/", soft())
    try key_cap(a, builder, s, faces, 1200usize, 118.0, 732.0, 130.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 254.0, 732.0, 44.0, ".", soft())
    try key_cap(a, builder, s, faces, 1205usize, 304.0, 732.0, 90.0, "Enter", amber())
    ret ok
}

// ---- the hosts.

fn draw_hosts(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 34.0, "Hosts", 24.0, 40.0, light())
    try put(a, builder, faces.grotesk, 12.0, "Local demo sessions, no network yet", 24.0, 86.0, light_muted())
    var row = 0usize
    var i = 0usize
    while i < MAX_HOSTS {
        if s.hosts[i].used {
            let h = s.hosts[i]
            let y: f32 = 112.0 + f32(row) * 80.0
            try card(a, builder, 16.0, y, 380.0, 68.0, 20.0, cream())
            try disc(a, builder, 50.0, y + 34.0, 22.0, tint_of(i))
            try svg.draw(a, builder, prompt_icon(), geometry.rect(38.0, y + 22.0, 24.0, 24.0), ink())
            try clipped(a, builder, faces.jost_bold, 18.0, alias_of(a, h), 86.0, y + 12.0, 230.0, ink())
            try clipped(a, builder, faces.grotesk, 13.0, join(a, join(a, user_of(a, h), "@", addr_of(a, h)), "", ""), 86.0, y + 40.0, 230.0, muted())
            var dot = soft()
            if h.seen { dot = paint.Color { red: 0.13, green: 0.52, blue: 0.28, alpha: 1.0 } }
            try disc(a, builder, 370.0, y + 22.0, 5.0, dot)
            try put(a, builder, faces.grotesk, 11.0, "edit", 356.0 - 8.0, y + 44.0, muted())
            hit(s, 100usize + i, 16.0, y, 300.0, 68.0)
            hit(s, 300usize + i, 316.0, y, 80.0, 68.0)
            row += 1usize
        }
        i += 1usize
    }
    try card(a, builder, 252.0, 780.0, 144.0, 56.0, 28.0, amber())
    try card(a, builder, 274.0 - 9.0, 808.0 - 1.5, 18.0, 3.0, 1.5, ink())
    try card(a, builder, 274.0 - 1.5, 808.0 - 9.0, 3.0, 18.0, 1.5, ink())
    try put(a, builder, faces.jost, 17.0, "New host", 298.0, 797.0, ink())
    hit(s, 150usize, 252.0, 780.0, 144.0, 56.0)
    ret ok
}

// ---- the form.

fn field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, which: usize, label: str, value: str, y: f32) -> err {
    try put(a, builder, faces.grotesk, 12.0, label, 20.0, y - 16.0, light_muted())
    if s.focus == which { try card(a, builder, 14.0, y - 2.0, 384.0, 52.0, 18.0, amber()) }
    try card(a, builder, 16.0, y, 380.0, 48.0, 16.0, cream())
    try clipped(a, builder, faces.jost, 19.0, value, 32.0, y + 12.0, 340.0, ink())
    if s.focus == which {
        var caret_x: f32 = 32.0
        if value.len > 0usize { caret_x = 32.0 + text.measure(a, faces.jost, 19.0, value) + 2.0 }
        if caret_x > 372.0 { caret_x = 372.0 }
        try card(a, builder, caret_x, y + 11.0, 2.0, 26.0, 1.0, amber())
    }
    hit(s, 1500usize + which, 16.0, y, 380.0, 48.0)
    ret ok
}

fn draw_form(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "New host"
    if s.editing != NONE { heading = "Edit host" }
    try put(a, builder, faces.jost_bold, 30.0, heading, 24.0, 28.0, light())
    try field(a, builder, s, faces, 0usize, "Alias", alias_of(a, s.draft), 90.0)
    try field(a, builder, s, faces, 1usize, "Address", addr_of(a, s.draft), 160.0)
    try field(a, builder, s, faces, 2usize, "User", user_of(a, s.draft), 230.0)
    // The port and the sign-in.
    var port_22 = soft()
    var port_2222 = soft()
    if s.draft.port == 22usize { port_22 = amber() } else { port_2222 = amber() }
    try put(a, builder, faces.grotesk, 12.0, "Port", 20.0, 284.0, light_muted())
    try pill(a, builder, s, faces, 1320usize, 16.0, 304.0, 60.0, 36.0, "22", port_22, 15.0)
    try pill(a, builder, s, faces, 1321usize, 72.0, 304.0, 76.0, 36.0, "2222", port_2222, 15.0)
    var password_fill = soft()
    var key_fill = soft()
    if s.draft.key_auth { key_fill = amber() } else { password_fill = amber() }
    try put(a, builder, faces.grotesk, 12.0, "Sign in with", 180.0, 284.0, light_muted())
    try pill(a, builder, s, faces, 1330usize, 180.0, 304.0, 120.0, 36.0, "Password", password_fill, 15.0)
    try pill(a, builder, s, faces, 1331usize, 308.0, 304.0, 88.0, 36.0, "Key", key_fill, 15.0)
    // Save, Connect and Cancel or Delete.
    try pill(a, builder, s, faces, 1300usize, 16.0, 366.0, 120.0, 48.0, "Save", amber(), 17.0)
    try pill(a, builder, s, faces, 1303usize, 146.0, 366.0, 120.0, 48.0, "Connect", soft(), 17.0)
    if s.editing != NONE {
        try pill(a, builder, s, faces, 1301usize, 276.0, 366.0, 120.0, 48.0, "Delete", soft(), 17.0)
    } else {
        try pill(a, builder, s, faces, 1302usize, 276.0, 366.0, 120.0, 48.0, "Cancel", soft(), 17.0)
    }
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

// ---- the terminal.

fn line_color(kind: usize) -> paint.Color {
    if kind == 1usize { ret paint.Color { red: 0.55, green: 0.82, blue: 0.62, alpha: 1.0 } }
    if kind == 2usize { ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 } }
    ret paint.Color { red: 0.86, green: 0.88, blue: 0.86, alpha: 1.0 }
}

fn extra_key(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, w: f32, label: str) -> err {
    try card(a, builder, x, 454.0, w, 36.0, 10.0, soft())
    try centred(a, builder, faces.grotesk, 15.0, label, x + w / 2.0, 454.0 + 18.0 - 10.0, ink())
    hit(s, id, x, 454.0, w, 36.0)
    ret ok
}

fn draw_terminal(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let h = s.hosts[s.current]
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 14.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 22.0, alias_of(a, h), 64.0, 16.0, light())
    try disc(a, builder, 72.0, 56.0, 4.0, paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 })
    try put(a, builder, faces.grotesk, 12.0, "demo session", 82.0, 49.0, light_muted())
    try card(a, builder, 16.0, 80.0, 380.0, 362.0, 16.0, paint.Color { red: 0.04, green: 0.05, blue: 0.06, alpha: 1.0 })
    var first = 0usize
    if s.line_total > VISIBLE { first = s.line_total - VISIBLE }
    var row = 0usize
    while first + row < s.line_total {
        let line = s.lines[first + row]
        try clipped(a, builder, faces.grotesk, 13.0, text_of(a, line.body[0usize..], line.length), 28.0, 92.0 + f32(row) * 18.0, 356.0, line_color(line.kind))
        row += 1usize
    }
    // The prompt with what is typed and a block cursor.
    let prompt = join(a, prompt_text(a, s), text_of(a, s.cmd[0usize..], s.cmd_len), "")
    let y: f32 = 92.0 + f32(row) * 18.0
    try clipped(a, builder, faces.grotesk, 13.0, prompt, 28.0, y, 356.0, line_color(1usize))
    var cursor_x = 28.0 + text.measure(a, faces.grotesk, 13.0, prompt) + 1.0
    if cursor_x > 380.0 { cursor_x = 380.0 }
    try card(a, builder, cursor_x, y + 1.0, 7.0, 15.0, 1.0, amber())
    // The extra keys.
    try extra_key(a, builder, s, faces, 1211usize, 16.0, 56.0, "~")
    try extra_key(a, builder, s, faces, 1212usize, 78.0, 56.0, "Up")
    try extra_key(a, builder, s, faces, 1213usize, 140.0, 56.0, "Down")
    try extra_key(a, builder, s, faces, 1214usize, 202.0, 92.0, "Ctrl-C")
    try extra_key(a, builder, s, faces, 1215usize, 300.0, 96.0, "Clear")
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.screen == HOSTS_SCREEN {
        try draw_hosts(a, builder, s, faces)
    } else if s.screen == FORM_SCREEN {
        try draw_form(a, builder, s, faces)
    } else {
        try draw_terminal(a, builder, s, faces)
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

// A character from the keyboard goes to the command in the terminal, or to the field in focus.
fn type_byte(s: *State, byte: u8) {
    if s.screen == TERMINAL_SCREEN {
        if s.cmd_len < 40usize {
            s.cmd[s.cmd_len] = byte
            s.cmd_len += 1usize
        }
        ret
    }
    if s.focus == 0usize && s.draft.alias_len < 16usize {
        s.draft.alias[s.draft.alias_len] = byte
        s.draft.alias_len += 1usize
    }
    if s.focus == 1usize && s.draft.addr_len < 24usize {
        s.draft.addr[s.draft.addr_len] = byte
        s.draft.addr_len += 1usize
    }
    if s.focus == 2usize && s.draft.user_len < 12usize {
        s.draft.user[s.draft.user_len] = byte
        s.draft.user_len += 1usize
    }
}

fn backspace(s: *State) {
    if s.screen == TERMINAL_SCREEN {
        if s.cmd_len > 0usize { s.cmd_len -= 1usize }
        ret
    }
    if s.focus == 0usize && s.draft.alias_len > 0usize { s.draft.alias_len -= 1usize }
    if s.focus == 1usize && s.draft.addr_len > 0usize { s.draft.addr_len -= 1usize }
    if s.focus == 2usize && s.draft.user_len > 0usize { s.draft.user_len -= 1usize }
}

fn open_form(s: *State, index: usize) {
    s.screen = FORM_SCREEN
    s.editing = index
    s.focus = 0usize
    if index == NONE {
        s.draft = make_host("", "", "", 22usize, false, false)
        s.draft.alias_len = 0usize
    } else {
        s.draft = s.hosts[index]
    }
}

// Keep the draft: a new host or the edited one. False when a field is empty.
fn save_draft(s: *State) -> bool {
    if s.draft.alias_len == 0usize || s.draft.addr_len == 0usize || s.draft.user_len == 0usize { ret false }
    if s.editing == NONE {
        if !add_host(s, s.draft) { ret false }
    } else {
        s.hosts[s.editing] = s.draft
    }
    say("ssh saved\n")
    ret true
}

// Put history entry `at` (0 = newest) on the command line.
fn recall(s: *State, at: usize) {
    var i = 0usize
    while i < s.history_len[at] {
        s.cmd[i] = s.history[at * 40usize + i]
        i += 1usize
    }
    s.cmd_len = s.history_len[at]
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == HOSTS_SCREEN {
        if id >= 100usize && id < 108usize {
            if s.hosts[id - 100usize].used {
                connect(a, s, id - 100usize)
                ret true
            }
            ret false
        }
        if id >= 300usize && id < 308usize {
            open_form(s, id - 300usize)
            ret true
        }
        if id == 150usize {
            if count_hosts(s) < MAX_HOSTS { open_form(s, NONE) }
            ret true
        }
        ret false
    }
    // The back arrow.
    if id == 500usize {
        s.screen = HOSTS_SCREEN
        if s.line_total > 0usize || s.cmd_len > 0usize { say("ssh closed\n") }
        ret true
    }
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
        backspace(s)
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
        type_byte(s, 47u8)
        ret true
    }
    if id == 1205usize {
        if s.screen == TERMINAL_SCREEN {
            run_command(a, s)
        } else if s.focus < 2usize {
            s.focus += 1usize
        }
        ret true
    }
    if s.screen == TERMINAL_SCREEN {
        if id == 1211usize {
            type_byte(s, 126u8)
            ret true
        }
        if id == 1212usize {
            if s.history_at < s.history_total {
                recall(s, s.history_at)
                s.history_at += 1usize
            }
            ret true
        }
        if id == 1213usize {
            if s.history_at > 1usize {
                s.history_at -= 1usize
                recall(s, s.history_at - 1usize)
            } else {
                s.history_at = 0usize
                s.cmd_len = 0usize
            }
            ret true
        }
        if id == 1214usize {
            push_line(s, join(a, prompt_text(a, s), text_of(a, s.cmd[0usize..], s.cmd_len), "^C"), 1usize)
            s.cmd_len = 0usize
            ret true
        }
        if id == 1215usize {
            s.line_total = 0usize
            ret true
        }
        ret false
    }
    // The form.
    if id >= 1500usize && id < 1503usize {
        s.focus = id - 1500usize
        ret true
    }
    if id == 1320usize {
        s.draft.port = 22usize
        ret true
    }
    if id == 1321usize {
        s.draft.port = 2222usize
        ret true
    }
    if id == 1330usize {
        s.draft.key_auth = false
        ret true
    }
    if id == 1331usize {
        s.draft.key_auth = true
        ret true
    }
    if id == 1300usize {
        if save_draft(s) { s.screen = HOSTS_SCREEN }
        ret true
    }
    if id == 1303usize {
        if save_draft(s) {
            var index = s.editing
            if index == NONE {
                index = 0usize
                while index < MAX_HOSTS && !(s.hosts[index].used && s.hosts[index].alias_len == s.draft.alias_len && s.hosts[index].addr_len == s.draft.addr_len) { index += 1usize }
            }
            if index < MAX_HOSTS { connect(a, s, index) } else { s.screen = HOSTS_SCREEN }
        }
        ret true
    }
    if id == 1301usize {
        if s.editing != NONE { s.hosts[s.editing].used = false }
        s.screen = HOSTS_SCREEN
        say("ssh deleted\n")
        ret true
    }
    if id == 1302usize {
        s.screen = HOSTS_SCREEN
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
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "ssh")
    if kit_error != ok {
        say("ssh open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("ssh fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.editing = NONE
    let h1 = add_host(&s, make_host("web-01", "10.0.1.21", "deploy", 22usize, true, true))
    let h2 = add_host(&s, make_host("db-primary", "10.0.2.5", "postgres", 22usize, true, false))
    let h3 = add_host(&s, make_host("lab-pi", "192.168.1.40", "pi", 22usize, false, true))
    let h4 = add_host(&s, make_host("build-runner", "ci.example.com", "runner", 2222usize, true, false))
    let h5 = add_host(&s, make_host("backup-nas", "nas.local", "admin", 22usize, false, false))
    if !show(a, &kit, &s) {
        say("ssh present failed\n")
        ret ok
    }
    say("ssh shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("ssh home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    say("ssh present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
