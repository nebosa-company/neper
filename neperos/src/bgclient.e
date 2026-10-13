// The client side of the background services process (C168, C174, C176, D4007): the process the kernel starts in the
// unified boot that keeps working when no app is in front -- the audio mixer behind e.audio (media, ring and alarm
// volumes and Vibrate come from the settings server), the clock's ringer (it holds the alarms and the timer and rings
// them with the Clock closed) and the notification poster. A launched app is granted its two endpoints in slots 13
// (requests out) and 14 (replies in); the kernel stamps the sender's app number in the top byte of every request, so
// a request cannot be made in another app's name. A request is ONE word (bits 0-3 op, 4-7 kind, 8-55 payload).
//
//   PLAY stream tone ms     -> peak: the loudest sample of the mixed block (a volume of 0 is silence)
//   RING_STATE              -> 0 when nothing rings, else (index + 1) | what << 8 | minutes << 16 (what 1 an alarm, 2 the timer)
//   RING_STOP               -> 1 (the ring stops, the notification stays counted)
//   FOREGROUND flag         -> none: the Clock is in front (flag 1), so the process leaves the ringing to it
//   SCHEDULE chunk bytes    -> none: six bytes of the Clock's 64-byte state, chunk 0 to 10
//   NOTIFY                  -> none: a notification through the status service
//   VOLUMES m r a v         -> none: from the settings server only (the kernel's stamp 0)
//   STATS                   -> beeps played, last peak, rings, notifications posted
use e.os

const REQ: usize = 13usize
const REP: usize = 14usize
const NO_SLOT: usize = 99usize
const REFUSED: usize = 18446744073709551615usize

const OP_PLAY: usize = 1usize
const OP_RING_STATE: usize = 2usize
const OP_RING_STOP: usize = 3usize
const OP_FOREGROUND: usize = 4usize
const OP_SCHEDULE: usize = 5usize
const OP_NOTIFY: usize = 6usize
const OP_VOLUMES: usize = 7usize
const OP_STATS: usize = 8usize
const OP_WALK: usize = 9usize

// The streams of the mixer, one volume each in Settings.
const STREAM_MEDIA: usize = 0usize
const STREAM_RING: usize = 1usize
const STREAM_ALARM: usize = 2usize

// What rings.
const RING_NONE: usize = 0usize
const RING_ALARM: usize = 1usize
const RING_TIMER: usize = 2usize

// The tones: a short beep, a two-note chime and the alarm's three beeps.
const TONE_BEEP: usize = 0usize
const TONE_CHIME: usize = 1usize
const TONE_ALARM: usize = 2usize

fn request(op: usize, kind: usize, payload: usize) -> usize {
    ret op | (kind << 4usize) | (payload << 8usize)
}

// Play `tone` on `stream` for `ms` milliseconds at the stream's volume; the loudest sample mixed (0 when silent or
// when there is no process), and whether the process answered.
fn play(stream: usize, tone: usize, ms: usize) -> (usize, bool) {
    let sent = os.send(REQ, request(OP_PLAY, stream, tone | (ms << 8usize)), NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    ret (os.recv(REP, NO_SLOT), true)
}

// Which alarm or timer rings now: its index, what it is (RING_ALARM or RING_TIMER) and the minute of the day it was set
// for, or index 99 when nothing rings.
fn ring_state() -> (usize, usize, usize) {
    let sent = os.send(REQ, request(OP_RING_STATE, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret (99usize, RING_NONE, 0usize) }
    let word = os.recv(REP, NO_SLOT)
    if word == 0usize { ret (99usize, RING_NONE, 0usize) }
    ret ((word & 255usize) - 1usize, (word >> 8usize) & 255usize, word >> 16usize)
}

fn ring_stop() -> bool {
    let sent = os.send(REQ, request(OP_RING_STOP, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret false }
    ret os.recv(REP, NO_SLOT) != 0usize
}

// Tell the process whether the Clock is in front (it rings in-app when it is).
fn foreground(on: bool) {
    var flag = 0usize
    if on { flag = 1usize }
    let sent = os.send(REQ, request(OP_FOREGROUND, 0usize, flag), NO_SLOT)
}

// The Clock's 64 bytes (alarms, timer, ...) to the process, six bytes a word.
fn schedule(bytes: []const u8) {
    var chunk = 0usize
    while chunk < 11usize {
        var payload = 0usize
        var k = 0usize
        while k < 6usize {
            let at = chunk * 6usize + k
            if at < bytes.len { payload = payload | (usize(bytes[at]) << (8usize * k)) }
            k += 1usize
        }
        let sent = os.send(REQ, request(OP_SCHEDULE, chunk, payload), NO_SLOT)
        if sent == REFUSED { ret }
        chunk += 1usize
    }
}

fn notify() {
    let sent = os.send(REQ, request(OP_NOTIFY, 0usize, 0usize), NO_SLOT)
}

// A goal or a milestone of an app that has no place in Settings' notification list (Steps): counted by the status
// service as the system's, not as one of the eight.
fn notify_goal() {
    let sent = os.send(REQ, request(OP_NOTIFY, 1usize, 0usize), NO_SLOT)
}

// Beeps played, the last peak, rings started and notifications posted.
fn stats() -> (usize, usize, usize, usize) {
    let sent = os.send(REQ, request(OP_STATS, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, 0usize, 0usize) }
    let beeps = os.recv(REP, NO_SLOT)
    let peak = os.recv(REP, NO_SLOT)
    let rings = os.recv(REP, NO_SLOT)
    let posted = os.recv(REP, NO_SLOT)
    ret (beeps, peak, rings, posted)
}
