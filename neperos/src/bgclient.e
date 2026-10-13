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

// (C166) The microphone and the speaker. The services process owns the capture buffer (ten seconds of 8 kHz mono 16-bit,
// the scripted microphone of power.e's sort: a pure function of the seed and the frame index until the Pixel's codec is
// behind the same calls) and the speaker's sink. A recording is the process's, not the app's: it runs while the app is
// closed, and the app that opens again finds it running (REC_STATE) and takes it (REC_READ).
//
//   REC_START seed          -> 0 started (or already running), 1 microphone access is off, 2 no capture
//   REC_STATE [leaving]     -> (kind 1: the app is leaving with the recording running, so it goes on unwatched) running | frames << 8 | peak << 40 (peak 0 to 100 of the newest 100 ms) | background << 48
//   REC_STOP                -> frames captured (the buffer stays for REC_READ)
//   REC_READ offset max     -> count, then count / 4 words (rounded up) of four 16-bit frames each, low frame first
//   SPK_WRITE words|frames<<16, flags -> frames taken; `words` data words follow (three frames each, 48 bits: the
//                              kernel's stamp owns the top byte; the last word may carry fewer than three frames);
//                              flag 1 starts a new stream (the counts reset)
//   SPK_STATS               -> frames, checksum (the byte sum of what reached the sink mod 65521), peak after the gain
const OP_REC_START: usize = 10usize
const OP_REC_STATE: usize = 11usize
const OP_REC_STOP: usize = 12usize
const OP_REC_READ: usize = 13usize
const OP_SPK_WRITE: usize = 14usize
const OP_SPK_STATS: usize = 15usize

const REC_OK: usize = 0usize
const REC_DENIED: usize = 1usize
const REC_NO_SERVER: usize = 2usize
// The capture buffer holds this many frames (ten seconds at 8 kHz).
const REC_FRAMES: usize = 80000usize
const REC_RATE: usize = 8000usize

fn rec_start(seed: usize) -> usize {
    let sent = os.send(REQ, request(OP_REC_START, seed & 15usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret REC_NO_SERVER }
    ret os.recv(REP, NO_SLOT)
}

// (running, frames captured, the level of the newest 100 ms 0..100, whether it ran unwatched).
fn rec_state(leaving: bool) -> (bool, usize, usize, bool) {
    var flag = 0usize
    if leaving { flag = 1usize }
    let sent = os.send(REQ, request(OP_REC_STATE, flag, 0usize), NO_SLOT)
    if sent == REFUSED { ret (false, 0usize, 0usize, false) }
    let word = os.recv(REP, NO_SLOT)
    ret ((word & 1usize) != 0usize, (word >> 8usize) & 4294967295usize, (word >> 40usize) & 255usize, ((word >> 48usize) & 1usize) != 0usize)
}

fn rec_stop() -> usize {
    let sent = os.send(REQ, request(OP_REC_STOP, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// Up to `max` frames (at most 256) from frame `offset` of the capture, as 16-bit little-endian samples at `dst`: how many.
fn rec_read(offset: usize, max: usize, dst: usize) -> usize {
    var want = max
    if want > 256usize { want = 256usize }
    let sent = os.send(REQ, request(OP_REC_READ, 0usize, offset | (want << 32usize)), NO_SLOT)
    if sent == REFUSED { ret 0usize }
    let count = os.recv(REP, NO_SLOT)
    var i = 0usize
    while i * 4usize < count {
        let word = os.recv(REP, NO_SLOT)
        var j = 0usize
        while j < 4usize && i * 4usize + j < count {
            let frame = (word >> (16usize * j)) & 65535usize
            os.store8(dst + (i * 4usize + j) * 2usize, u8(frame & 255usize))
            os.store8(dst + (i * 4usize + j) * 2usize + 1usize, u8(frame >> 8usize))
            j += 1usize
        }
        i += 1usize
    }
    ret count
}

// Write `frames` frames of 16-bit little-endian samples from `src` to the speaker; `begin` starts a new stream. The
// number taken (the process answers per block of up to 96 frames, so a longer buffer is several calls).
fn spk_write(src: usize, frames: usize, begin: bool) -> usize {
    var done = 0usize
    var first = begin
    while done < frames {
        var block = frames - done
        if block > 96usize { block = 96usize }
        let words = (block + 2usize) / 3usize
        var flags = 0usize
        if first { flags = 1usize }
        first = false
        let sent = os.send(REQ, request(OP_SPK_WRITE, flags, words | (block << 16usize)), NO_SLOT)
        if sent == REFUSED { ret done }
        var w = 0usize
        while w < words {
            var packed = 0usize
            var j = 0usize
            while j < 3usize {
                var frame = 0usize
                if w * 3usize + j < block {
                    let at = src + (done + w * 3usize + j) * 2usize
                    frame = usize(os.load8(at)) | (usize(os.load8(at + 1usize)) << 8usize)
                }
                packed = packed | (frame << (16usize * j))
                j += 1usize
            }
            let word_sent = os.send(REQ, packed, NO_SLOT)
            w += 1usize
        }
        let taken = os.recv(REP, NO_SLOT)
        done += block
    }
    ret done
}

// (frames, checksum, peak) of what reached the speaker since the stream began.
fn spk_stats() -> (usize, usize, usize) {
    let sent = os.send(REQ, request(OP_SPK_STATS, 0usize, 0usize), NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, 0usize) }
    let frames = os.recv(REP, NO_SLOT)
    let sum = os.recv(REP, NO_SLOT)
    let peak = os.recv(REP, NO_SLOT)
    ret (frames, sum, peak)
}
