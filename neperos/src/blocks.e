// Blocks (D2234): the falling-blocks game behind the Blocks icon -- a board of ten by twenty cells, seven
// kinds of piece in a shuffled bag, the next piece shown, a score, the lines cleared and a level. The
// piece falls with the input server's ticks (one row each half second, more at higher levels); the buttons
// move it left and right, turn it, drop it a row, or drop it all the way; Pause stops the fall and Restart
// begins again. A full row clears; one, two, three or four rows at once score 100, 300, 500 and 800 times
// the level. Dark ground, cream and amber with a colour for each piece, like the other apps (appkit.e,
// taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: the fall is tied to the 500 ms tick, so the fastest the pieces can come down by themselves is
// one row each half second (the level adds rows for each tick instead); the buttons are the only way to
// be faster. Held keys, hold, a ghost piece, high scores kept in storage and sound are queued as C139.
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
use ui
use vaultfs
use bgclient

const NONE: usize = 99usize
// (C169, D4008) The auto-repeat of a held button: the delay before the first repeat and the interval after it, in ms.
const REPEAT_DELAY: usize = 250usize
const REPEAT_EVERY: usize = 90usize
// The board's rectangle in dp, for the drag and the swipe.
fn board_x() -> f32 { ret 12.0 }
fn board_y() -> f32 { ret 84.0 }
fn board_w() -> f32 { ret 248.0 }
fn board_h() -> f32 { ret 488.0 }

// While set, the moves of an auto-repeat do not say each step on the serial line.
var silent: bool = false

fn note(line: str) {
    if !silent { ui.say(line) }
}

fn now_ms() -> usize {
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret 0usize }
    ret usize(now.nanos / 1000000i64)
}

// The milliseconds a row takes to fall at `level`: half a second at the first, a sixth less each level, and fifty (twenty
// rows a second) from the fifteenth.
fn fall_ms(level: usize) -> usize {
    var ms = 500usize
    var l = 1usize
    while l < level && ms > 50usize {
        ms = ms * 85usize / 100usize
        l += 1usize
    }
    if ms < 50usize { ms = 50usize }
    ret ms
}
const COLS: usize = 10usize
const ROWS: usize = 20usize
fn cell_size() -> f32 {
    ret 24.0
}

type State = struct {
    board: [200]u8,
    piece: usize,
    rot: usize,
    px: i32,
    py: i32,
    next: usize,
    bag: [7]u8,
    bag_at: usize,
    seed: usize,
    score: usize,
    lines: usize,
    level: usize,
    paused: bool,
    over: bool,
    pieces: usize,
    // (C139) The piece held back (NONE when none) and whether it was swapped in for this piece already, and the
    // best score kept in /blocks.
    hold: usize,
    hold_used: bool,
    best: usize,
    // (C169) The score board: the five best games and the last game, kept with the best in /blocks.
    top: [5]usize,
    top_count: usize,
    last: usize,
    // (C169, D4008) The fall's clock (the monotonic ms the next row is due), the button being held and when it repeats
    // next, a drag on the board (where it began, the cells it has moved, whether it moved at all) and whether the screen
    // is behind the game (drawn at the next tick).
    next_fall: usize,
    held_id: usize,
    repeat_at: usize,
    drag_active: bool,
    drag_x: f32,
    drag_y: f32,
    drag_cells: i32,
    drag_moved: bool,
    dirty: bool,
    // Practice: the pieces do not fall by themselves (Down and Drop still move them).
    manual: bool,
    hits: ui.Hits,
}

// The four rotations of the seven pieces as 4 x 4 bit masks, the top left cell the highest bit.
fn mask(piece: usize, rot: usize) -> usize {
    if piece == 0usize {
        if rot == 0usize { ret 0x0F00usize }
        if rot == 1usize { ret 0x2222usize }
        if rot == 2usize { ret 0x00F0usize }
        ret 0x4444usize
    }
    if piece == 1usize {
        if rot == 0usize { ret 0x8E00usize }
        if rot == 1usize { ret 0x6440usize }
        if rot == 2usize { ret 0x0E20usize }
        ret 0x44C0usize
    }
    if piece == 2usize {
        if rot == 0usize { ret 0x2E00usize }
        if rot == 1usize { ret 0x4460usize }
        if rot == 2usize { ret 0x0E80usize }
        ret 0xC440usize
    }
    if piece == 3usize { ret 0x6600usize }
    if piece == 4usize {
        if rot == 0usize { ret 0x6C00usize }
        if rot == 1usize { ret 0x4620usize }
        if rot == 2usize { ret 0x06C0usize }
        ret 0x8C40usize
    }
    if piece == 5usize {
        if rot == 0usize { ret 0x4E00usize }
        if rot == 1usize { ret 0x4640usize }
        if rot == 2usize { ret 0x0E40usize }
        ret 0x4C40usize
    }
    if rot == 0usize { ret 0xC600usize }
    if rot == 1usize { ret 0x2640usize }
    if rot == 2usize { ret 0x0C60usize }
    ret 0x4C80usize
}

fn piece_color(piece: usize) -> paint.Color {
    if piece == 0usize { ret paint.Color { red: 0.50, green: 0.80, blue: 0.85, alpha: 1.0 } }
    if piece == 1usize { ret paint.Color { red: 0.50, green: 0.60, blue: 0.90, alpha: 1.0 } }
    if piece == 2usize { ret paint.Color { red: 0.92, green: 0.65, blue: 0.40, alpha: 1.0 } }
    if piece == 3usize { ret paint.Color { red: 0.95, green: 0.82, blue: 0.45, alpha: 1.0 } }
    if piece == 4usize { ret paint.Color { red: 0.55, green: 0.82, blue: 0.55, alpha: 1.0 } }
    if piece == 5usize { ret paint.Color { red: 0.78, green: 0.58, blue: 0.85, alpha: 1.0 } }
    ret paint.Color { red: 0.90, green: 0.50, blue: 0.48, alpha: 1.0 }
}

// Is cell `i` (0..15) of the piece in rotation `rot` filled?
fn filled(piece: usize, rot: usize, i: usize) -> bool {
    ret (mask(piece, rot) >> (15usize - i)) & 1usize == 1usize
}

// Would the piece fit with its 4 x 4 box at (x, y)?
fn fits(s: *State, piece: usize, rot: usize, x: i32, y: i32) -> bool {
    var i = 0usize
    while i < 16usize {
        if filled(piece, rot, i) {
            let cx = x + i32(i % 4usize)
            let cy = y + i32(i / 4usize)
            if cx < 0i32 || cx >= i32(COLS) || cy >= i32(ROWS) { ret false }
            if cy >= 0i32 && s.board[usize(cy) * COLS + usize(cx)] != 0u8 { ret false }
        }
        i += 1usize
    }
    ret true
}

// The next piece of the shuffled bag of seven.
fn draw_from_bag(s: *State) -> usize {
    if s.bag_at >= 7usize {
        var i = 0usize
        while i < 7usize {
            s.bag[i] = u8(i)
            i += 1usize
        }
        var k = 6usize
        while k > 0usize {
            s.seed = (s.seed * 1103515245usize + 12345usize) & 2147483647usize
            let j = (s.seed >> 8usize) % (k + 1usize)
            let t = s.bag[k]
            s.bag[k] = s.bag[j]
            s.bag[j] = t
            k -= 1usize
        }
        s.bag_at = 0usize
    }
    let p = usize(s.bag[s.bag_at])
    s.bag_at += 1usize
    ret p
}

// A sound of the game on the media stream: a click as a piece locks, a chime for lines, the alarm's burst at the end.
fn sound(tone: usize, ms: usize, what: str) {
    let (peak, served) = bgclient.play(bgclient.STREAM_MEDIA, tone, ms)
    if served {
        ui.say("blocks sound ")
        ui.say(what)
        ui.say("\n")
    }
}

fn spawn(s: *State) {
    s.piece = s.next
    s.next = draw_from_bag(s)
    s.rot = 0usize
    s.px = 3i32
    s.py = -1i32
    s.hold_used = false
    s.pieces += 1usize
    if !fits(s, s.piece, s.rot, s.px, s.py) {
        s.over = true
        ui.say("blocks game over\n")
        sound(bgclient.TONE_ALARM, 300usize, "over")
        finish_game(s)
    }
}

fn restart(s: *State) {
    var i = 0usize
    while i < 200usize {
        s.board[i] = 0u8
        i += 1usize
    }
    s.score = 0usize
    s.lines = 0usize
    s.level = 1usize
    s.hold = NONE
    s.hold_used = false
    s.over = false
    s.paused = false
    s.pieces = 0usize
    s.bag_at = 7usize
    s.next = draw_from_bag(s)
    spawn(s)
}

// The piece lands: its cells join the board, full rows clear, the next piece comes.
fn lock(s: *State) {
    var i = 0usize
    while i < 16usize {
        if filled(s.piece, s.rot, i) {
            let cx = s.px + i32(i % 4usize)
            let cy = s.py + i32(i / 4usize)
            if cy >= 0i32 && cy < i32(ROWS) && cx >= 0i32 && cx < i32(COLS) { s.board[usize(cy) * COLS + usize(cx)] = u8(s.piece + 1usize) }
        }
        i += 1usize
    }
    var cleared = 0usize
    var row = ROWS
    while row > 0usize {
        row -= 1usize
        var full = true
        var c = 0usize
        while c < COLS {
            if s.board[row * COLS + c] == 0u8 { full = false }
            c += 1usize
        }
        if full {
            // Everything above moves down a row, and this row is checked again.
            var r = row
            while r > 0usize {
                var c2 = 0usize
                while c2 < COLS {
                    s.board[r * COLS + c2] = s.board[(r - 1usize) * COLS + c2]
                    c2 += 1usize
                }
                r -= 1usize
            }
            var c3 = 0usize
            while c3 < COLS {
                s.board[c3] = 0u8
                c3 += 1usize
            }
            cleared += 1usize
            row += 1usize
        }
    }
    if cleared > 0usize {
        var points = 100usize
        if cleared == 2usize { points = 300usize }
        if cleared == 3usize { points = 500usize }
        if cleared >= 4usize { points = 800usize }
        s.score += points * s.level
        s.lines += cleared
        s.level = 1usize + s.lines / 10usize
        ui.say("blocks lines ")
        ui.say_num(s.lines)
        ui.say(" score ")
        ui.say_num(s.score)
        ui.say("\n")
        sound(bgclient.TONE_CHIME, 200usize, "lines")
    } else {
        sound(bgclient.TONE_BEEP, 40usize, "lock")
    }
    spawn(s)
}

// One row down: true if it moved, false if it landed.
fn step_down(s: *State) -> bool {
    if fits(s, s.piece, s.rot, s.px, s.py + 1i32) {
        s.py += 1i32
        ret true
    }
    lock(s)
    ret false
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn put_word(buf: []u8, at: usize, value: usize) {
    var i = 0usize
    while i < 4usize {
        buf[at + i] = u8((value >> (8usize * i)) & 255usize)
        i += 1usize
    }
}

fn get_word(buf: []const u8, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize {
        v = v | (usize(buf[at + i]) << (8usize * i))
        i += 1usize
    }
    ret v
}

// /blocks is 28 bytes: the best score, the five best games (highest first, zero for none) and the last game, four
// bytes each, little end. A four-byte file from before is just the best.
fn save_board(s: *State) {
    var buf: [28]u8 = zero
    put_word(buf[0usize..28usize], 0usize, s.best)
    var i = 0usize
    while i < 5usize {
        put_word(buf[0usize..28usize], 4usize + 4usize * i, s.top[i])
        i += 1usize
    }
    put_word(buf[0usize..28usize], 24usize, s.last)
    let kept = vaultfs.write("/blocks", mem.address_of(&buf[0usize]), 28usize)
}

// A hard drop that beats the best keeps it at once (a game left half-way still counts).
fn save_best(s: *State) {
    if s.score <= s.best { ret }
    s.best = s.score
    save_board(s)
}

// The game just ended: it is the last game, and goes into the five best when it is high enough.
fn finish_game(s: *State) {
    s.last = s.score
    if s.score > s.best { s.best = s.score }
    if s.score > 0usize {
        var at = 0usize
        while at < 5usize && s.top[at] >= s.score { at += 1usize }
        if at < 5usize {
            var k = 4usize
            while k > at {
                s.top[k] = s.top[k - 1usize]
                k -= 1usize
            }
            s.top[at] = s.score
        }
    }
    var count = 0usize
    while count < 5usize && s.top[count] > 0usize { count += 1usize }
    s.top_count = count
    save_board(s)
}

fn load_best(s: *State) {
    var buf: [28]u8 = zero
    let (n, found) = vaultfs.read("/blocks", mem.address_of(&buf[0usize]), 28usize)
    if !found || n < 4usize { ret }
    s.best = get_word(buf[0usize..28usize], 0usize)
    if n >= 28usize {
        var i = 0usize
        while i < 5usize {
            s.top[i] = get_word(buf[0usize..28usize], 4usize + 4usize * i)
            i += 1usize
        }
        s.last = get_word(buf[0usize..28usize], 24usize)
    }
    var count = 0usize
    while count < 5usize && s.top[count] > 0usize { count += 1usize }
    s.top_count = count
}

// The row the piece in play would stop at if dropped now.
fn ghost_y(s: *State) -> i32 {
    var y = s.py
    var guard = 0usize
    while fits(s, s.piece, s.rot, s.px, y + 1i32) && guard < 30usize {
        y += 1i32
        guard += 1usize
    }
    ret y
}

fn cell(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, c: paint.Color) -> err {
    try ui.card(a, builder, x + 1.0, y + 1.0, cell_size() - 2.0, cell_size() - 2.0, 5.0, c)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.07, 0.08, 0.10)
    try ui.put(a, builder, faces.jost_bold, 26.0, "Blocks", 20.0, 16.0, ui.light())
    // The board.
    try ui.card(a, builder, 12.0, 84.0, 248.0, 488.0, 12.0, paint.Color { red: 0.13, green: 0.14, blue: 0.17, alpha: 1.0 })
    var r = 0usize
    while r < ROWS {
        var c = 0usize
        while c < COLS {
            let v = s.board[r * COLS + c]
            if v != 0u8 { try cell(a, builder, 16.0 + f32(c) * cell_size(), 88.0 + f32(r) * cell_size(), piece_color(usize(v) - 1usize)) }
            c += 1usize
        }
        r += 1usize
    }
    // Where the piece will land, then the piece in play.
    if !s.over {
        let gy = ghost_y(s)
        var g = 0usize
        while g < 16usize {
            if filled(s.piece, s.rot, g) {
                let cy = gy + i32(g / 4usize)
                if cy >= 0i32 && gy != s.py { try ui.card(a, builder, 16.0 + f32(s.px + i32(g % 4usize)) * cell_size() + 1.0, 88.0 + f32(cy) * cell_size() + 1.0, cell_size() - 3.0, cell_size() - 3.0, 4.0, paint.Color { red: 0.35, green: 0.37, blue: 0.42, alpha: 0.7 }) }
            }
            g += 1usize
        }
        var i = 0usize
        while i < 16usize {
            if filled(s.piece, s.rot, i) {
                let cy = s.py + i32(i / 4usize)
                if cy >= 0i32 { try cell(a, builder, 16.0 + f32(s.px + i32(i % 4usize)) * cell_size(), 88.0 + f32(cy) * cell_size(), piece_color(s.piece)) }
            }
            i += 1usize
        }
    }
    // The side: score, level, lines, the next piece.
    try ui.card(a, builder, 272.0, 84.0, 124.0, 488.0, 12.0, ui.cream())
    try ui.put(a, builder, faces.grotesk, 11.0, "Score", 284.0, 96.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 22.0, ui.number(a, s.score), 284.0, 112.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 11.0, "Level", 284.0, 156.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 22.0, ui.number(a, s.level), 284.0, 172.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 11.0, "Lines", 284.0, 216.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 22.0, ui.number(a, s.lines), 284.0, 232.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 11.0, "Next", 284.0, 286.0, ui.muted())
    var n = 0usize
    while n < 16usize {
        if filled(s.next, 0usize, n) { try ui.card(a, builder, 288.0 + f32(n % 4usize) * 20.0, 308.0 + f32(n / 4usize) * 20.0, 18.0, 18.0, 4.0, piece_color(s.next)) }
        n += 1usize
    }
    // The held piece and the best score.
    try ui.put(a, builder, faces.grotesk, 11.0, "Hold", 284.0, 400.0, ui.muted())
    if s.hold != NONE {
        var h = 0usize
        while h < 16usize {
            if filled(s.hold, 0usize, h) { try ui.card(a, builder, 288.0 + f32(h % 4usize) * 20.0, 420.0 + f32(h / 4usize) * 20.0, 18.0, 18.0, 4.0, piece_color(s.hold)) }
            h += 1usize
        }
    }
    try ui.put(a, builder, faces.grotesk, 11.0, "Best", 284.0, 516.0, ui.muted())
    try ui.put(a, builder, faces.jost_bold, 18.0, ui.number(a, s.best), 284.0, 532.0, ui.ink())
    if s.paused { try ui.centred(a, builder, faces.jost_bold, 20.0, "Paused", 334.0, 420.0, ui.amber_dark()) }
    if s.over {
        try ui.card(a, builder, 28.0, 250.0, 216.0, 130.0, 18.0, ui.cream())
        try ui.centred(a, builder, faces.jost_bold, 24.0, "Game over", 136.0, 272.0, ui.ink())
        try ui.centred(a, builder, faces.jost, 16.0, ui.join(a, "Score ", ui.number(a, s.score), ""), 136.0, 310.0, ui.muted())
        // The three best games.
        var rank = 0usize
        while rank < 3usize && rank < s.top_count {
            try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.join(a, ui.number(a, rank + 1usize), ". ", ""), ui.number(a, s.top[rank]), ""), 40.0 + f32(rank) * 64.0, 336.0 - 0.0, ui.muted())
            rank += 1usize
        }
        try ui.pill(a, builder, &s.hits, faces, 130usize, 56.0, 352.0, 160.0, 28.0, "Play again", ui.amber(), 15.0)
    }
    // The buttons.
    try ui.pill(a, builder, &s.hits, faces, 100usize, 16.0, 596.0, 120.0, 52.0, "Left", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 101usize, 146.0, 596.0, 120.0, 52.0, "Turn", ui.amber(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 102usize, 276.0, 596.0, 120.0, 52.0, "Right", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 103usize, 16.0, 664.0, 120.0, 52.0, "Down", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 104usize, 146.0, 664.0, 120.0, 52.0, "Drop", ui.amber(), 18.0)
    var pause_label = "Pause"
    if s.paused { pause_label = "Resume" }
    try ui.pill(a, builder, &s.hits, faces, 105usize, 276.0, 664.0, 120.0, 52.0, pause_label, ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 107usize, 16.0, 732.0, 90.0, 44.0, "Hold", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 106usize, 116.0, 732.0, 110.0, 44.0, "Restart", ui.soft(), 16.0)
    var fall_label = "Fall: auto"
    var fall_fill = ui.soft()
    if s.manual {
        fall_label = "Fall: manual"
        fall_fill = ui.amber()
    }
    try ui.pill(a, builder, &s.hits, faces, 108usize, 236.0, 732.0, 160.0, 44.0, fall_label, fall_fill, 16.0)
    try ui.handle(a, builder)
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

fn act(s: *State, id: usize) -> bool {
    if s.over {
        if id == 130usize || id == 106usize {
            restart(s)
            ui.say("blocks restart\n")
            ret true
        }
        ret false
    }
    if id == 106usize {
        restart(s)
        ui.say("blocks restart\n")
        ret true
    }
    if id == 108usize {
        s.manual = !s.manual
        if s.manual {
            // Practice starts a game afresh with the fixed seed (what fell while the mode was being chosen is undone).
            s.seed = 20261008usize
            restart(s)
            ui.say("blocks fall manual\n")
        } else {
            ui.say("blocks fall auto\n")
        }
        ret true
    }
    if id == 105usize {
        s.paused = !s.paused
        ui.say("blocks pause\n")
        ret true
    }
    if s.paused { ret false }
    if id == 100usize {
        if fits(s, s.piece, s.rot, s.px - 1i32, s.py) { s.px -= 1i32 }
        note("blocks move left\n")
        ret true
    }
    if id == 102usize {
        if fits(s, s.piece, s.rot, s.px + 1i32, s.py) { s.px += 1i32 }
        note("blocks move right\n")
        ret true
    }
    if id == 101usize {
        let turned = (s.rot + 1usize) % 4usize
        // A turn that does not fit is kicked: a cell or two to either side, then a cell up.
        let kicks_x: [6]i32 = [6]i32{ 0i32, -1i32, 1i32, -2i32, 2i32, 0i32 }
        let kicks_y: [6]i32 = [6]i32{ 0i32, 0i32, 0i32, 0i32, 0i32, -1i32 }
        var k = 0usize
        var done = false
        while k < 6usize && !done {
            if fits(s, s.piece, turned, s.px + kicks_x[k], s.py + kicks_y[k]) {
                s.rot = turned
                s.px += kicks_x[k]
                s.py += kicks_y[k]
                done = true
            }
            k += 1usize
        }
        ui.say("blocks rotate\n")
        ret true
    }
    if id == 103usize {
        let moved = step_down(s)
        ret true
    }
    if id == 104usize {
        var guard = 0usize
        while fits(s, s.piece, s.rot, s.px, s.py + 1i32) && guard < 30usize {
            s.py += 1i32
            guard += 1usize
        }
        // Two points a row for a hard drop.
        s.score += 2usize * guard
        lock(s)
        save_best(s)
        ui.say("blocks drop\n")
        ret true
    }
    if id == 107usize {
        if s.hold_used { ret false }
        if s.hold == NONE {
            s.hold = s.piece
            spawn(s)
        } else {
            let swapped = s.hold
            s.hold = s.piece
            s.piece = swapped
            s.rot = 0usize
            s.px = 3i32
            s.py = -1i32
            if !fits(s, s.piece, s.rot, s.px, s.py) {
                s.over = true
                ui.say("blocks game over\n")
                finish_game(s)
            }
        }
        s.hold_used = true
        ui.say("blocks hold\n")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "blocks")
    if kit_error != ok {
        ui.say("blocks open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("blocks fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.seed = 20261008usize
    load_best(&s)
    if s.best > 0usize {
        ui.say("blocks best ")
        ui.say_num(s.best)
        ui.say("\n")
    }
    if s.top_count > 0usize {
        ui.say("blocks board ")
        ui.say_num(s.top_count)
        ui.say(" last ")
        ui.say_num(s.last)
        ui.say("\n")
    }
    restart(&s)
    s.held_id = NONE
    s.next_fall = now_ms() + fall_ms(s.level)
    if !show(a, &kit, &s) {
        ui.say("blocks present failed\n")
        ret ok
    }
    ui.say("blocks shown\n")
    var running = true
    while running {
        // The app wakes when a row is due or a held button repeats; the kernel's receive deadline is the clock.
        var wait = 0usize
        if !s.paused && !s.over && (!s.manual || s.held_id != NONE) {
            let now = now_ms()
            var due = s.next_fall
            if s.manual { due = s.repeat_at }
            if s.held_id != NONE && s.repeat_at < due { due = s.repeat_at }
            wait = 1usize
            if due > now { wait = due - now }
        }
        let touch = appkit.next_touch(&kit, wait)
        if touch.kind == appkit.TOUCH_TIMEOUT {
            let now = now_ms()
            if s.held_id != NONE && now >= s.repeat_at && !s.paused && !s.over {
                silent = true
                if act(&s, s.held_id) { s.dirty = true }
                silent = false
                s.repeat_at = now + REPEAT_EVERY
            }
            // A pause (or a long frame) leaves the clock behind: it starts again from now, not from where it was.
            if now >= s.next_fall + 1500usize { s.next_fall = now + fall_ms(s.level) }
            // Rows that are due fall, a few at most at once (a long frame is not a free run of the board).
            var rows = 0usize
            while !s.paused && !s.over && !s.manual && now >= s.next_fall && rows < 4usize {
                let moved = step_down(&s)
                s.next_fall += fall_ms(s.level)
                s.dirty = true
                rows += 1usize
                if !moved { rows = 4usize }
            }
        } else if touch.kind == appkit.TOUCH_END {
            running = false
        } else if touch.kind == appkit.TOUCH_TICK {
            // The half-second tick draws what the game did since the last frame.
            if s.dirty {
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                s.dirty = false
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if touch.kind == appkit.TOUCH_DOWN {
            if touch.y >= 896.0 {
                ui.say("blocks home\n")
                appkit.leave()
                running = false
            } else if touch.x >= board_x() && touch.x < board_x() + board_w() && touch.y >= board_y() && touch.y < board_y() + board_h() && !s.over && !s.paused {
                // A finger on the board: a drag moves the piece, a swipe down drops it, a tap turns it.
                s.drag_active = true
                s.drag_x = touch.x
                s.drag_y = touch.y
                s.drag_cells = 0i32
                s.drag_moved = false
                appkit.answer(appkit.ANSWER_NONE)
            } else {
                let id = ui.hit_at(&s.hits, touch.x, touch.y)
                if id != ui.NONE && act(&s, id) {
                    // Left, Right and Down repeat while the finger stays on them.
                    if id == 100usize || id == 102usize || id == 103usize { s.held_id = id }
                    if !show(a, &kit, &s) {
                        ui.say("blocks present failed\n")
                        appkit.answer(appkit.ANSWER_NONE)
                    }
                    // The delay counts from the end of the frame (a frame outlasts it under emulation, and the
                    // release of a quick tap is already waiting).
                    s.repeat_at = now_ms() + REPEAT_DELAY
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            }
        } else if touch.kind == appkit.TOUCH_MOVE {
            if s.drag_active && !s.over && !s.paused {
                // One cell for each 24 dp the finger has moved sideways since it touched down.
                let cells = i32((touch.x - s.drag_x) / cell_size())
                var guard = 0usize
                while s.drag_cells < cells && guard < 12usize {
                    if fits(&s, s.piece, s.rot, s.px + 1i32, s.py) { s.px += 1i32 }
                    s.drag_cells += 1i32
                    s.drag_moved = true
                    s.dirty = true
                    guard += 1usize
                }
                while s.drag_cells > cells && guard < 24usize {
                    if fits(&s, s.piece, s.rot, s.px - 1i32, s.py) { s.px -= 1i32 }
                    s.drag_cells -= 1i32
                    s.drag_moved = true
                    s.dirty = true
                    guard += 1usize
                }
            }
            appkit.answer(appkit.ANSWER_NONE)
        } else if touch.kind == appkit.TOUCH_UP {
            var drew = false
            if s.held_id != NONE {
                ui.say("blocks released px ")
                ui.say_num(usize(s.px))
                ui.say("\n")
                s.held_id = NONE
            }
            if s.drag_active {
                s.drag_active = false
                let dx = touch.x - s.drag_x
                let dy = touch.y - s.drag_y
                var adx = dx
                if adx < 0.0 { adx = 0.0 - adx }
                if s.drag_moved {
                    ui.say("blocks drag px ")
                    ui.say_num(usize(s.px))
                    ui.say("\n")
                    s.dirty = true
                } else if dy > 60.0 && dy > 2.0 * adx {
                    // A swipe down: the piece goes all the way.
                    ui.say("blocks swipe\n")
                    if act(&s, 104usize) { s.dirty = true }
                } else if adx < 10.0 && dy < 10.0 && dy > -10.0 {
                    // A tap on the board turns the piece.
                    if act(&s, 101usize) { s.dirty = true }
                }
            }
            if s.dirty {
                if show(a, &kit, &s) { drew = true }
                s.dirty = false
            }
            if !drew { appkit.answer(appkit.ANSWER_NONE) }
        } else {
            appkit.answer(appkit.ANSWER_NONE)
        }
    }
    ret ok
}
