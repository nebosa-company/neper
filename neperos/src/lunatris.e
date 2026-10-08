// Lunatris (D2234): the falling-blocks game behind the Lunatris icon -- a board of ten by twenty cells, seven
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
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui

const NONE: usize = 99usize
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

fn spawn(s: *State) {
    s.piece = s.next
    s.next = draw_from_bag(s)
    s.rot = 0usize
    s.px = 3i32
    s.py = -1i32
    s.pieces += 1usize
    if !fits(s, s.piece, s.rot, s.px, s.py) {
        s.over = true
        ui.say("lunatris game over\n")
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
        ui.say("lunatris lines ")
        ui.say_num(s.lines)
        ui.say("\n")
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

fn cell(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, c: paint.Color) -> err {
    try ui.card(a, builder, x + 1.0, y + 1.0, cell_size() - 2.0, cell_size() - 2.0, 5.0, c)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.07, 0.08, 0.10)
    try ui.put(a, builder, faces.jost_bold, 26.0, "Lunatris", 20.0, 16.0, ui.light())
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
    // The piece in play.
    if !s.over {
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
    if s.paused { try ui.centred(a, builder, faces.jost_bold, 20.0, "Paused", 334.0, 420.0, ui.amber_dark()) }
    if s.over {
        try ui.card(a, builder, 28.0, 250.0, 216.0, 130.0, 18.0, ui.cream())
        try ui.centred(a, builder, faces.jost_bold, 24.0, "Game over", 136.0, 272.0, ui.ink())
        try ui.centred(a, builder, faces.jost, 16.0, ui.join(a, "Score ", ui.number(a, s.score), ""), 136.0, 310.0, ui.muted())
        try ui.pill(a, builder, &s.hits, faces, 130usize, 56.0, 336.0, 160.0, 36.0, "Play again", ui.amber(), 15.0)
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
    try ui.pill(a, builder, &s.hits, faces, 106usize, 106.0, 732.0, 200.0, 44.0, "Restart", ui.soft(), 16.0)
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
            ui.say("lunatris restart\n")
            ret true
        }
        ret false
    }
    if id == 106usize {
        restart(s)
        ui.say("lunatris restart\n")
        ret true
    }
    if id == 105usize {
        s.paused = !s.paused
        ui.say("lunatris pause\n")
        ret true
    }
    if s.paused { ret false }
    if id == 100usize {
        if fits(s, s.piece, s.rot, s.px - 1i32, s.py) { s.px -= 1i32 }
        ui.say("lunatris move left\n")
        ret true
    }
    if id == 102usize {
        if fits(s, s.piece, s.rot, s.px + 1i32, s.py) { s.px += 1i32 }
        ui.say("lunatris move right\n")
        ret true
    }
    if id == 101usize {
        let turned = (s.rot + 1usize) % 4usize
        // A turn that does not fit may be pushed a cell to either side.
        if fits(s, s.piece, turned, s.px, s.py) {
            s.rot = turned
        } else if fits(s, s.piece, turned, s.px - 1i32, s.py) {
            s.rot = turned
            s.px -= 1i32
        } else if fits(s, s.piece, turned, s.px + 1i32, s.py) {
            s.rot = turned
            s.px += 1i32
        }
        ui.say("lunatris rotate\n")
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
        lock(s)
        ui.say("lunatris drop\n")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "lunatris")
    if kit_error != ok {
        ui.say("lunatris open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("lunatris fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.seed = 20261008usize
    restart(&s)
    if !show(a, &kit, &s) {
        ui.say("lunatris present failed\n")
        ret ok
    }
    ui.say("lunatris shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The piece falls: a row a tick, and one more for every three levels.
            if !s.paused && !s.over {
                var rows = 1usize + (s.level - 1usize) / 3usize
                while rows > 0usize && !s.over {
                    let moved = step_down(&s)
                    rows -= 1usize
                    if !moved { rows = 0usize }
                }
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("lunatris home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    ui.say("lunatris present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
